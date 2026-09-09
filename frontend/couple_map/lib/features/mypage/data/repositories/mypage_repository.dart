import 'package:dio/dio.dart';
import '../../../../core/network/dio_client.dart';
import '../../../../core/network/s3_uploader.dart';
import '../../../auth/data/models/user_model.dart';
import 'dart:io';

class MypageRepository {
  Future<UserModel> getUserInfo() async {
    try {
      final response = await DioClient.instance.get('/api/users/me');
      return UserModel.fromJson(response.data['data'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw DioClient.handleError(e);
    }
  }

  Future<String> updateNickname(String nickname) async {
    try {
      final response = await DioClient.instance.post(
        '/api/users/nickname',
        data: {'nickname': nickname},
      );
      return response.data['data']['nickname'] as String;
    } on DioException catch (e) {
      throw DioClient.handleError(e);
    }
  }

  Future<String> uploadProfileImage(File imageFile) async {
    try {
      final issued = await S3Uploader.uploadImage(imageFile);
      final response = await DioClient.instance.post(
        '/api/users/profile-image',
        data: {
          'uploadId': issued.uploadId,
          'fileKey': issued.fileKeys.first,
        },
      );
      return response.data['data']['imageUrl'] as String;
    } on DioException catch (e) {
      throw DioClient.handleError(e);
    }
  }

  Future<void> deleteProfileImage() async {
    try {
      await DioClient.instance.delete('/api/users/profile-image');
    } on DioException catch (e) {
      throw DioClient.handleError(e);
    }
  }

  Future<void> deleteAccount() async {
    try {
      await DioClient.instance.delete('/api/users/me');
    } on DioException catch (e) {
      throw DioClient.handleError(e);
    }
  }
}
