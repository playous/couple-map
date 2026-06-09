import 'package:dio/dio.dart';
import '../../../../core/network/dio_client.dart';
import '../models/notification_model.dart';

class NotificationRepository {
  Future<List<NotificationModel>> getNotifications() async {
    try {
      final results = await Future.wait([
        DioClient.instance.get('/api/friend/list/pending'),
        DioClient.instance.get('/api/map/invitations'),
      ]);

      final friendData =
          results[0].data['data']['friendPendingInfoDtoList'] as List? ?? [];
      final mapData = results[1].data['data'] as List? ?? [];

      final friendNotifications = friendData
          .map((j) => NotificationModel.fromFriendRequest(j as Map<String, dynamic>))
          .toList();

      final mapNotifications = mapData
          .map((j) => NotificationModel.fromMapInvitation(j as Map<String, dynamic>))
          .toList();

      return [...friendNotifications, ...mapNotifications];
    } on DioException catch (e) {
      throw DioClient.handleError(e);
    }
  }
}
