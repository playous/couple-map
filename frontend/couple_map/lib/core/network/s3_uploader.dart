import 'dart:io';
import 'package:dio/dio.dart';
import 'dio_client.dart';

class IssuedUpload {
  final String uploadId;
  final List<String> fileKeys;

  IssuedUpload(this.uploadId, this.fileKeys);
}

class S3Uploader {
  S3Uploader._();

  // 서명된 URL은 헤더 집합이 고정이라 Authorization이 붙으면 S3가 403을 준다
  static final Dio _s3 = Dio();

  // 프로필 이미지 · 지도 배경
  static Future<IssuedUpload> uploadImage(File file) async {
    final bytes = await file.readAsBytes();
    final contentType = contentTypeOf(file);

    final res = await DioClient.instance.post(
      '/api/uploads/image',
      data: {
        'filename': fileNameOf(file),
        'contentType': contentType,
        'size': bytes.length,
      },
    );
    final data = res.data['data'] as Map<String, dynamic>;

    await _put(data['url'] as String, bytes, contentType);

    return IssuedUpload(data['uploadId'] as String, [data['fileKey'] as String]);
  }

  // 추억 첨부 파일 (여러 개)
  static Future<IssuedUpload> uploadMemoryFiles(int mapId, List<File> files) async {
    final bytesList = <List<int>>[];
    final specs = <Map<String, dynamic>>[];

    for (final file in files) {
      final bytes = await file.readAsBytes();
      bytesList.add(bytes);
      specs.add({
        'filename': fileNameOf(file),
        'contentType': contentTypeOf(file),
        'size': bytes.length,
      });
    }

    final res = await DioClient.instance.post(
      '/api/maps/$mapId/memories/uploads',
      data: {'files': specs},
    );
    final data = res.data['data'] as Map<String, dynamic>;
    final items = (data['items'] as List).cast<Map<String, dynamic>>();

    await Future.wait(List.generate(items.length, (i) {
      return _put(items[i]['url'] as String, bytesList[i], specs[i]['contentType'] as String);
    }));

    return IssuedUpload(
      data['uploadId'] as String,
      items.map((e) => e['fileKey'] as String).toList(),
    );
  }

  static Future<void> _put(String url, List<int> bytes, String contentType) async {
    await _s3.put(
      url,
      data: bytes,
      options: Options(
        headers: {
          'Content-Type': contentType,
          Headers.contentLengthHeader: bytes.length,
        },
      ),
    );
  }

  static String fileNameOf(File file) =>
      file.path.split(Platform.pathSeparator).last.split('/').last;

  static String contentTypeOf(File file) {
    final ext = file.path.split('.').last.toLowerCase();
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'mp4':
        return 'video/mp4';
      case 'mov':
        return 'video/quicktime';
      case 'mp3':
        return 'audio/mpeg';
      case 'm4a':
        return 'audio/x-m4a';
      default:
        return 'image/jpeg';
    }
  }
}
