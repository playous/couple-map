import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import '../../../../core/network/dio_client.dart';
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

  // 추억 생성
  Future<int> createMemory(
    int mapId,
    Map<String, dynamic> requestData,
    List<File>? imageFiles,
  ) async {
    try {
      final formData = FormData();
      formData.files.add(MapEntry(
        'request',
        MultipartFile.fromString(
          jsonEncode(requestData),
          contentType: DioMediaType.parse('application/json'),
        ),
      ));
      if (imageFiles != null) {
        for (final file in imageFiles) {
          formData.files.add(MapEntry(
            'files',
            await MultipartFile.fromFile(file.path,
                filename: file.path.split('/').last),
          ));
        }
      }
      final response = await DioClient.instance.post(
        '/api/maps/$mapId/memories',
        data: formData,
      );
      return response.data['data'] as int;
    } on DioException catch (e) {
      throw DioClient.handleError(e);
    }
  }

  Future<void> updateMemory(
    int mapId,
    int memoryId,
    Map<String, dynamic> requestData,
    List<File>? files,
  ) async {
    try {
      final formData = FormData();
      formData.files.add(MapEntry(
        'request',
        MultipartFile.fromString(
          jsonEncode(requestData),
          contentType: DioMediaType.parse('application/json'),
        ),
      ));
      if (files != null) {
        for (final file in files) {
          formData.files.add(MapEntry(
            'files',
            await MultipartFile.fromFile(file.path,
                filename: file.path.split('/').last),
          ));
        }
      }
      await DioClient.instance.put(
        '/api/maps/$mapId/memories/$memoryId',
        data: formData,
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
