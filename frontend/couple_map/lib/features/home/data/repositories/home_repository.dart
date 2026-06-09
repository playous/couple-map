import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import '../../../../core/network/dio_client.dart';
import '../models/map_card_model.dart';

class HomeRepository {
  // 지도 목록 조회
  Future<List<MapCardModel>> getMapList() async {
    try {
      final response = await DioClient.instance.get('/api/map');
      final data = response.data['data'] as List;
      return data.map((json) => MapCardModel.fromJson(json as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      throw DioClient.handleError(e);
    }
  }

  // 지도 생성 (multipart/form-data)
  Future<int> createMap(
    String mapName,
    String? description,
    String category, [
    File? backgroundImage,
  ]) async {
    try {
      final requestJson = jsonEncode({
        'mapName': mapName,
        if (description != null) 'description': description,
        'category': category,
      });
      final formData = FormData.fromMap({
        'request': MultipartFile.fromString(
          requestJson,
          contentType: DioMediaType('application', 'json'),
        ),
        if (backgroundImage != null)
          'backgroundImage': await MultipartFile.fromFile(backgroundImage.path),
      });
      final response = await DioClient.instance.post(
        '/api/map',
        data: formData,
        options: Options(contentType: 'multipart/form-data'),
      );
      return response.data['data'] as int;
    } on DioException catch (e) {
      throw DioClient.handleError(e);
    }
  }
}
