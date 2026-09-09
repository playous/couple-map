import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/notification_model.dart';
import '../../data/repositories/notification_repository.dart';

final notificationRepositoryProvider =
    Provider<NotificationRepository>((_) => NotificationRepository());

class NotificationNotifier extends AsyncNotifier<List<NotificationModel>> {
  @override
  Future<List<NotificationModel>> build() async => [];

  Future<void> load() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(notificationRepositoryProvider).getNotifications(),
    );
  }

  void removeById(String id) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(current.where((n) => n.id != id).toList());
  }
}

final notificationProvider =
    AsyncNotifierProvider<NotificationNotifier, List<NotificationModel>>(
        NotificationNotifier.new);
