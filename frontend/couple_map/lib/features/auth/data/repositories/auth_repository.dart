import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:kakao_flutter_sdk/kakao_flutter_sdk.dart';
import 'package:flutter_naver_login/flutter_naver_login.dart';
import 'package:flutter_naver_login/interface/types/naver_login_status.dart';
import '../../../../core/network/dio_client.dart';
import '../models/auth_token.dart';

class AuthRepository {
  final _storage = const FlutterSecureStorage();
  final _googleSignIn = GoogleSignIn(scopes: ['email', 'profile']);

  static const _accessTokenKey = 'accessToken';
  static const _refreshTokenKey = 'refreshToken';

  // ── 소셜 로그인 ────────────────────────────────────────────

  Future<AuthToken> loginWithKakao() async {
    try {
      final installed = await isKakaoTalkInstalled();
      final token = installed
          ? await UserApi.instance.loginWithKakaoTalk()
          : await UserApi.instance.loginWithKakaoAccount();
      return await _loginWithProvider('/api/login/social/kakao', token.accessToken);
    } catch (e) {
      throw '카카오 로그인 실패: $e';
    }
  }

  Future<AuthToken> loginWithGoogle() async {
    try {
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) throw '구글 로그인이 취소되었습니다.';
      final googleAuth = await googleUser.authentication;
      if (googleAuth.accessToken == null) throw '구글 액세스 토큰을 가져올 수 없습니다.';
      return await _loginWithProvider('/api/login/social/google', googleAuth.accessToken!);
    } catch (e) {
      throw '구글 로그인 실패: $e';
    }
  }

  Future<AuthToken> loginWithNaver() async {
    try {
      final result = await FlutterNaverLogin.logIn();
      if (result.status != NaverLoginStatus.loggedIn) {
        throw '네이버 로그인이 취소되었습니다.';
      }
      final naverToken = await FlutterNaverLogin.getCurrentAccessToken();
      if (!naverToken.isValid()) throw '네이버 액세스 토큰이 유효하지 않습니다.';
      return await _loginWithProvider('/api/login/social/naver', naverToken.accessToken);
    } catch (e) {
      throw '네이버 로그인 실패: $e';
    }
  }

  Future<AuthToken> _loginWithProvider(String endpoint, String socialToken) async {
    try {
      final response = await DioClient.instance.post(
        endpoint,
        data: {'accessToken': socialToken},
      );
      final data = response.data['data'];
      if (data == null) throw Exception('응답 데이터가 없습니다.');
      return AuthToken.fromJson(data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw DioClient.handleError(e);
    }
  }

  // ── 토큰 저장/조회 ──────────────────────────────────────────

  Future<void> saveToken(AuthToken token) async {
    await _storage.write(key: _accessTokenKey, value: token.accessToken);
    if (token.refreshToken != null) {
      await _storage.write(key: _refreshTokenKey, value: token.refreshToken);
    }
  }

  Future<String?> getAccessToken() => _storage.read(key: _accessTokenKey);

  Future<void> clearToken() async {
    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _refreshTokenKey);
  }

  // ── 닉네임 설정 ──────────────────────────────────────────────

  Future<void> setNickname(String nickname) async {
    try {
      await DioClient.instance.post(
        '/api/users/nickname',
        data: {'nickname': nickname},
      );
    } on DioException catch (e) {
      throw DioClient.handleError(e);
    }
  }

  // ── 로그아웃 ──────────────────────────────────────────────────

  Future<void> logout() async {
    try {
      await DioClient.instance.post('/api/auth/logout');
    } on DioException catch (_) {
      // 로그아웃은 서버 실패해도 로컬 토큰 삭제
    } finally {
      await clearToken();
    }
  }
}

