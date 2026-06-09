import 'package:dio/dio.dart';
import '../../../../core/network/dio_client.dart';

class FriendInfo {
  final int id;
  final String nickname;
  final String? imageUrl;
  final String? friendCode;

  const FriendInfo({
    required this.id,
    required this.nickname,
    this.imageUrl,
    this.friendCode,
  });

  factory FriendInfo.fromJson(Map<String, dynamic> json) {
    return FriendInfo(
      id: json['id'] as int,
      nickname: json['nickname'] as String,
      imageUrl: json['imageUrl'] as String?,
      friendCode: json['friendCode'] as String?,
    );
  }
}

class FriendPendingInfo {
  final int friendshipId;
  final String nickname;
  final String? imageUrl;

  const FriendPendingInfo({
    required this.friendshipId,
    required this.nickname,
    this.imageUrl,
  });

  factory FriendPendingInfo.fromJson(Map<String, dynamic> json) {
    return FriendPendingInfo(
      friendshipId: json['friendshipId'] as int,
      nickname: json['nickname'] as String,
      imageUrl: json['imageUrl'] as String?,
    );
  }
}

class FriendRepository {
  Future<List<FriendInfo>> getFriendList() async {
    try {
      final response = await DioClient.instance.get('/api/friend/list');
      final data = response.data['data']['friendList'] as List;
      return data.map((j) => FriendInfo.fromJson(j as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      throw DioClient.handleError(e);
    }
  }

  Future<List<FriendPendingInfo>> getPendingFriendList() async {
    try {
      final response = await DioClient.instance.get('/api/friend/list/pending');
      final data = response.data['data']['friendPendingInfoDtoList'] as List;
      return data.map((j) => FriendPendingInfo.fromJson(j as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      throw DioClient.handleError(e);
    }
  }

  Future<void> sendFriendRequest(String friendCode) async {
    try {
      await DioClient.instance.post(
        '/api/friend/request',
        data: {'friendCode': friendCode},
      );
    } on DioException catch (e) {
      throw DioClient.handleError(e);
    }
  }

  Future<void> acceptFriendRequest(int friendshipId) async {
    try {
      await DioClient.instance.post('/api/friend/$friendshipId/accept');
    } on DioException catch (e) {
      throw DioClient.handleError(e);
    }
  }

  Future<void> rejectFriendRequest(int friendshipId) async {
    try {
      await DioClient.instance.post('/api/friend/$friendshipId/reject');
    } on DioException catch (e) {
      throw DioClient.handleError(e);
    }
  }
}
