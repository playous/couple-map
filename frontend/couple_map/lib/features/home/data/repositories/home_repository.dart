import 'dart:io';
import 'package:dio/dio.dart';
import '../../../../core/network/dio_client.dart';
import '../../../../core/network/s3_uploader.dart';
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

  // 지도 생성 — 배경은 S3에 직접 올리고 키만 보낸다
  Future<int> createMap(
    String mapName,
    String? description,
    String category, [
    File? backgroundImage,
  ]) async {
    try {
      IssuedUpload? issued;
      if (backgroundImage != null) {
        issued = await S3Uploader.uploadImage(backgroundImage);
      }
      final response = await DioClient.instance.post(
        '/api/map',
        data: {
          'mapName': mapName,
          if (description != null) 'description': description,
          'category': category,
          if (issued != null) 'uploadId': issued.uploadId,
          if (issued != null) 'backgroundKey': issued.fileKeys.first,
        },
      );
      return response.data['data'] as int;
    } on DioException catch (e) {
      throw DioClient.handleError(e);
    }
  }
}
