import 'dart:io';
import 'package:dio/dio.dart';
import '../../../../core/network/dio_client.dart';
import '../../../../core/network/s3_uploader.dart';
import '../models/map_model.dart';

class MapRepository {
  // 지도 초대 목록 조회
  Future<List<MapInvitation>> getMapInvitations() async {
    try {
      final response = await DioClient.instance.get('/api/map/invitations');
      final data = response.data['data'] as List;
      return data.map((json) => MapInvitation.fromJson(json as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      throw DioClient.handleError(e);
    }
  }

  // 친구를 지도에 초대
  Future<void> inviteFriendToMap(int mapId, int friendId) async {
    try {
      await DioClient.instance.post(
        '/api/map/$mapId/invite',
        data: {'friendId': friendId},
      );
    } on DioException catch (e) {
      throw DioClient.handleError(e);
    }
  }

  // 지도 초대 수락
  Future<void> acceptMapInvitation(int mapMemberId) async {
    try {
      await DioClient.instance.post('/api/map/member/$mapMemberId/accept');
    } on DioException catch (e) {
      throw DioClient.handleError(e);
    }
  }

  // 지도 초대 거절
  Future<void> rejectMapInvitation(int mapMemberId) async {
    try {
      await DioClient.instance.post('/api/map/member/$mapMemberId/reject');
    } on DioException catch (e) {
      throw DioClient.handleError(e);
    }
  }

  // 지도 상세 조회
  Future<MapModel> getMapDetail(int mapId) async {
    try {
      final response = await DioClient.instance.get('/api/map/$mapId');
      return MapModel.fromJson(response.data['data'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw DioClient.handleError(e);
    }
  }

  // 지도 수정 — 배경은 S3에 직접 올리고 키만 보낸다
  Future<void> updateMap(
    int mapId,
    String mapName,
    String? description, [
    String? category,
    File? backgroundImage,
  ]) async {
    try {
      IssuedUpload? issued;
      if (backgroundImage != null) {
        issued = await S3Uploader.uploadImage(backgroundImage);
      }
      await DioClient.instance.put(
        '/api/map/$mapId',
        data: {
          'mapName': mapName,
          if (description != null) 'description': description,
          if (category != null) 'category': category,
          if (issued != null) 'uploadId': issued.uploadId,
          if (issued != null) 'backgroundKey': issued.fileKeys.first,
        },
      );
    } on DioException catch (e) {
      throw DioClient.handleError(e);
    }
  }

  // 지도 멤버 목록 조회
  Future<List<MapMemberInfo>> getMapMembers(int mapId) async {
    try {
      final response = await DioClient.instance.get('/api/map/$mapId/members');
      final data = response.data['data'] as List;
      return data.map((json) => MapMemberInfo.fromJson(json as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      throw DioClient.handleError(e);
    }
  }

  // 지도 삭제
  Future<void> deleteMap(int mapId) async {
    try {
      await DioClient.instance.delete('/api/map/$mapId');
    } on DioException catch (e) {
      throw DioClient.handleError(e);
    }
  }
}
