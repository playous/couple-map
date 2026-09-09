import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../config/app_config.dart';

class DioClient {
  DioClient._();

  static VoidCallback? onUnauthorized;
  static Future<String>? _refreshFuture;
  static const _storage = FlutterSecureStorage();

  static Dio get instance => _dio;

  // JWT payload에서 만료 5분 전 여부 체크
  static bool _isExpiringSoon(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return false;
      final payload = base64Url.normalize(parts[1]);
      final decoded = utf8.decode(base64Url.decode(payload));
      final json = jsonDecode(decoded) as Map<String, dynamic>;
      final exp = json['exp'] as int?;
      if (exp == null) return false;
      final expiry = DateTime.fromMillisecondsSinceEpoch(exp * 1000);
      return expiry.isBefore(DateTime.now().add(const Duration(minutes: 5)));
    } catch (_) {
      return false;
    }
  }

  static Future<String?> _doRefresh() async {
    final refreshToken = await _storage.read(key: 'refreshToken');
    if (refreshToken == null) return null;

    final refreshResponse = await Dio().post(
      '${AppConfig.baseUrl}/api/auth/refresh',
      options: Options(headers: {
        'Authorization': 'Bearer $refreshToken',
        'Content-Type': 'application/json',
      }),
    );

    final newAccessToken =
        refreshResponse.data['data']['accessToken'] as String;
    final newRefreshToken =
        refreshResponse.data['data']['refreshToken'] as String?;
    await _storage.write(key: 'accessToken', value: newAccessToken);
    if (newRefreshToken != null) {
      await _storage.write(key: 'refreshToken', value: newRefreshToken);
    }
    return newAccessToken;
  }

  // onRequest, onError 어디서 호출해도 재발급은 딱 한 번만
  static Future<String> _refreshGate() {
    _refreshFuture ??= _doRefresh().then((token) {
      if (token == null) throw Exception('refresh_failed');
      return token;
    }).whenComplete(() {
      _refreshFuture = null;
    });
    return _refreshFuture!;
  }

  static final Dio _dio = Dio(
    BaseOptions(
      baseUrl: AppConfig.baseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'Content-Type': 'application/json'},
    ),
  )..interceptors.add(InterceptorsWrapper(
      // ── 요청 전: storage의 토큰을 단일 출처로 주입 + 만료 5분 전이면 미리 refresh ──
      onRequest: (options, handler) async {
        // 로그인 엔드포인트는 인증 토큰이 필요 없으므로 건너뛴다.
        if (options.path.contains('/api/login/')) {
          return handler.next(options);
        }

        var token = await _storage.read(key: 'accessToken');
        if (token == null || token.isEmpty) return handler.next(options);

        if (_isExpiringSoon(token)) {
          try {
            token = await _refreshGate();
          } catch (_) {}
        }
        options.headers['Authorization'] = 'Bearer $token';
        return handler.next(options);
      },

      // ── 401 응답: 안전망 ──
      onError: (error, handler) async {
        if (error.response?.statusCode != 401) {
          return handler.next(error);
        }

        // 재시도한 요청이 또 401 나면 무한 루프 방지
        if (error.requestOptions.extra['_retried'] == true) {
          await _storage.delete(key: 'accessToken');
          await _storage.delete(key: 'refreshToken');
          onUnauthorized?.call();
          return handler.next(error);
        }

        try {
          final newToken = await _refreshGate();
          error.requestOptions.headers['Authorization'] = 'Bearer $newToken';
          error.requestOptions.extra['_retried'] = true;
          final retryResponse = await _dio.fetch(error.requestOptions);
          return handler.resolve(retryResponse);
        } catch (_) {
          await _storage.delete(key: 'accessToken');
          await _storage.delete(key: 'refreshToken');
          onUnauthorized?.call();
          return handler.next(error);
        }
      },
    ));

  static String handleError(DioException e) {
    if (e.response != null) {
      final message = e.response?.data['message'];
      return message?.toString() ?? '요청에 실패했습니다.';
    }
    return '네트워크 연결을 확인해주세요.';
  }
}
