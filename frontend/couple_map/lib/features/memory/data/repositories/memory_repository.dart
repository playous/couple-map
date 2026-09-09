import 'dart:io';
import 'package:dio/dio.dart';
import '../../../../core/network/dio_client.dart';
import '../../../../core/network/s3_uploader.dart';
import '../models/memory_model.dart';

class MemoryRepository {
  // 추억 목록 조회 (페이징)
  Future<({List<MemorySummary> items, bool hasNext})> getMemoryList(
    int mapId, {
    int page = 0,
    int size = 10,
  }) async {
    try {
      final response = await DioClient.instance.get(
        '/api/maps/$mapId/memories',
        queryParameters: {'page': page, 'size': size},
      );
      final data = response.data['data'] as Map<String, dynamic>?;
      if (data == null) return (items: <MemorySummary>[], hasNext: false);
      final items = (data['content'] as List)
          .map((json) => MemorySummary.fromJson(json as Map<String, dynamic>))
          .toList();
      return (items: items, hasNext: data['hasNext'] as bool? ?? false);
    } on DioException catch (e) {
      throw DioClient.handleError(e);
    }
  }

  // 마커 조회 (전체, 좌표만)
  Future<List<MemoryMarker>> getMemoryMarkers(int mapId) async {
    try {
      final response = await DioClient.instance.get(
        '/api/maps/$mapId/memories/markers',
      );
      final data = response.data['data'];
      if (data == null) return [];
      return (data as List)
          .map((json) => MemoryMarker.fromJson(json as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw DioClient.handleError(e);
    }
  }

  // 추억 상세 조회
  Future<MemoryModel> getMemoryDetail(int mapId, int memoryId) async {
    try {
      final response = await DioClient.instance.get(
        '/api/maps/$mapId/memories/$memoryId',
      );
      return MemoryModel.fromJson(response.data['data'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw DioClient.handleError(e);
    }
  }

  // 추억 생성 — 발급 -> S3 직접 업로드 -> 완료 통보
  Future<int> createMemory(
    int mapId,
    Map<String, dynamic> requestData,
    List<File>? imageFiles,
  ) async {
    final files = imageFiles ?? const <File>[];
    if (files.isEmpty) {
      return _createTextMemory(mapId, requestData);
    }

    try {
      final issued = await S3Uploader.uploadMemoryFiles(mapId, files);
      final response = await DioClient.instance.post(
        '/api/maps/$mapId/memories/complete',
        data: {
          'uploadId': issued.uploadId,
          'request': requestData,
          'files': _fileRefs(issued.fileKeys, 1),
        },
      );
      return response.data['data'] as int;
    } on DioException catch (e) {
      throw DioClient.handleError(e);
    }
  }

  // 파일 없는 추억은 전송할 바이트가 없어 presigned가 의미 없다
  Future<int> _createTextMemory(
    int mapId,
    Map<String, dynamic> requestData,
  ) async {
    try {
      final response = await DioClient.instance.post(
        '/api/maps/$mapId/memories',
        data: requestData,
      );
      return response.data['data'] as int;
    } on DioException catch (e) {
      throw DioClient.handleError(e);
    }
  }

  List<Map<String, dynamic>> _fileRefs(List<String> fileKeys, int startOrder) {
    return List.generate(fileKeys.length, (i) {
      return {'fileKey': fileKeys[i], 'displayOrder': startOrder + i};
    });
  }

  // 추억 수정 — 새 파일도 S3에 직접 올리고 키만 보낸다
  Future<void> updateMemory(
    int mapId,
    int memoryId,
    Map<String, dynamic> requestData,
    List<File>? files,
  ) async {
    try {
      final newFiles = files ?? const <File>[];
      IssuedUpload? issued;
      if (newFiles.isNotEmpty) {
        issued = await S3Uploader.uploadMemoryFiles(mapId, newFiles);
      }
      await DioClient.instance.put(
        '/api/maps/$mapId/memories/$memoryId',
        data: {
          ...requestData,
          if (issued != null) 'uploadId': issued.uploadId,
          if (issued != null) 'files': _fileRefs(issued.fileKeys, 1),
        },
      );
    } on DioException catch (e) {
      throw DioClient.handleError(e);
    }
  }

  Future<void> deleteMemory(int mapId, int memoryId) async {
    try {
      await DioClient.instance.delete(
        '/api/maps/$mapId/memories/$memoryId',
      );
    } on DioException catch (e) {
      throw DioClient.handleError(e);
    }
  }
}
