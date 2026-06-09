import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../data/models/notification_model.dart';
import '../../domain/providers/notification_provider.dart';
import '../../../../core/network/dio_client.dart';
import '../../../friend/domain/providers/friend_provider.dart';

class NotificationScreen extends ConsumerStatefulWidget {
  const NotificationScreen({super.key});

  @override
  ConsumerState<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends ConsumerState<NotificationScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(notificationProvider.notifier).load();
    });
  }

  Future<void> _handleInviteAction(String id, bool accepted, int? friendshipId, int? mapMemberId) async {
    if (friendshipId == null && mapMemberId == null) return;
    try {
      if (friendshipId != null) {
        if (accepted) {
          await ref.read(friendRepositoryProvider).acceptFriendRequest(friendshipId);
        } else {
          await ref.read(friendRepositoryProvider).rejectFriendRequest(friendshipId);
        }
      } else if (mapMemberId != null) {
        final action = accepted ? 'accept' : 'reject';
        try {
          await DioClient.instance.post('/api/map/member/$mapMemberId/$action');
        } on DioException catch (e) {
          throw DioClient.handleError(e);
        }
      }
      ref.read(notificationProvider.notifier).removeById(id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('요청 처리에 실패했어요. 다시 시도해주세요.'),
            backgroundColor: const Color(0xFFFF8E8E),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(notificationProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFFDFBF7),
      body: Column(
        children: [
          _buildAppBar(),
          Expanded(
            child: state.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: Color(0xFFFF8E8E)),
              ),
              error: (e, _) => Center(
                child: Text(
                  e.toString(),
                  style: const TextStyle(color: Color(0xFF888888)),
                ),
              ),
              data: (notifications) => notifications.isEmpty
                  ? _buildEmptyState()
                  : _buildNotificationList(notifications),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar() {
    return SafeArea(
      bottom: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 10, 24, 15),
        decoration: const BoxDecoration(
          color: Color(0xFFFDFBF7),
          border: Border(bottom: BorderSide(color: Color(0xFFF0ECE8))),
        ),
        child: Row(
          children: [
            GestureDetector(
              onTap: () {
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go('/');
                }
              },
              child: const Icon(Icons.arrow_back_ios, color: Color(0xFF191919), size: 20),
            ),
            const Expanded(
              child: Text(
                '알림',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'NotoSansKR',
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF2C2C2C),
                ),
              ),
            ),
            const SizedBox(width: 22),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Text(
            '알림이 없어요',
            style: TextStyle(
              fontFamily: 'NotoSansKR',
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: Color(0xFF2C2C2C),
            ),
          ),
          SizedBox(height: 8),
          Text(
            '새로운 소식이 도착하면\n여기서 확인할 수 있어요',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'NotoSansKR',
              fontSize: 13,
              fontWeight: FontWeight.w300,
              color: Color(0xFF888888),
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationList(List<NotificationModel> notifications) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 10),
          child: Text(
            '새 알림',
            style: TextStyle(
              fontFamily: 'NotoSansKR',
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Color(0xFFAAAAAA),
              letterSpacing: 0.8,
            ),
          ),
        ),
        ...notifications.map(
          (n) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _NotificationCard(
              notification: n,
              onAction: (id, accepted) =>
                  _handleInviteAction(id, accepted, n.friendshipId, n.mapMemberId),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// 알림 카드
// ─────────────────────────────────────────────
class _NotificationCard extends StatelessWidget {
  final NotificationModel notification;
  final void Function(String id, bool accepted)? onAction;

  const _NotificationCard({required this.notification, this.onAction});

  String get _icon {
    switch (notification.type) {
      case NotificationType.invite:
        return '🏝️';
      case NotificationType.mapInvite:
        return '🗺️';
      case NotificationType.memory:
        return '📸';
      case NotificationType.join:
        return '🎉';
      case NotificationType.other:
        return '🔔';
    }
  }

  List<Color> get _iconBg {
    switch (notification.type) {
      case NotificationType.invite:
        return [const Color(0xFFE0F2FF), const Color(0xFFC8E6FF)];
      case NotificationType.mapInvite:
        return [const Color(0xFFE0F7F0), const Color(0xFFC8EFE0)];
      case NotificationType.memory:
        return [const Color(0xFFFFE0E0), const Color(0xFFFFC8C8)];
      case NotificationType.join:
        return [const Color(0xFFFFEECC), const Color(0xFFFFDDA0)];
      case NotificationType.other:
        return [const Color(0xFFF0F0F0), const Color(0xFFE0E0E0)];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(color: Color(0x0D000000), blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: _iconBg,
              ),
            ),
            child: Center(child: Text(_icon, style: const TextStyle(fontSize: 18))),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildRichText(),
                const SizedBox(height: 4),
                Text(
                  notification.timeAgo,
                  style: const TextStyle(
                    fontFamily: 'NotoSansKR',
                    fontSize: 11,
                    fontWeight: FontWeight.w300,
                    color: Color(0xFFBBBBBB),
                  ),
                ),
                if (notification.hasAction) ...[
                  const SizedBox(height: 10),
                  _buildActionButtons(),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRichText() {
    final msg = notification.message;
    final bold = notification.boldPart;
    final highlight = notification.highlightPart;

    List<InlineSpan> spans = [];

    if (bold.isNotEmpty && msg.contains(bold)) {
      final parts = msg.split(bold);
      for (int i = 0; i < parts.length; i++) {
        if (parts[i].isNotEmpty) spans.add(_normalSpan(parts[i]));
        if (i < parts.length - 1) spans.add(_boldSpan(bold));
      }
    } else {
      spans.add(_normalSpan(msg));
    }

    if (highlight != null && highlight.isNotEmpty) {
      final List<InlineSpan> newSpans = [];
      for (final span in spans) {
        if (span is TextSpan && (span.text?.contains(highlight) ?? false)) {
          final sub = span.text!.split(highlight);
          for (int i = 0; i < sub.length; i++) {
            if (sub[i].isNotEmpty) newSpans.add(_normalSpan(sub[i]));
            if (i < sub.length - 1) newSpans.add(_highlightSpan(highlight));
          }
        } else {
          newSpans.add(span);
        }
      }
      spans = newSpans;
    }

    return Text.rich(TextSpan(children: spans));
  }

  TextSpan _normalSpan(String text) => TextSpan(
        text: text,
        style: const TextStyle(
          fontFamily: 'NotoSansKR',
          fontSize: 14,
          fontWeight: FontWeight.w300,
          color: Color(0xFF2C2C2C),
          height: 1.5,
        ),
      );

  TextSpan _boldSpan(String text) => TextSpan(
        text: text,
        style: const TextStyle(
          fontFamily: 'NotoSansKR',
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: Color(0xFF2C2C2C),
          height: 1.5,
        ),
      );

  TextSpan _highlightSpan(String text) => TextSpan(
        text: text,
        style: const TextStyle(
          fontFamily: 'NotoSansKR',
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: Color(0xFFFF8E8E),
          height: 1.5,
        ),
      );

  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: () => onAction?.call(notification.id, true),
            child: Container(
              height: 34,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                gradient: const LinearGradient(
                  begin: Alignment(0.19, -0.98),
                  end: Alignment(-0.19, 0.98),
                  colors: [Color(0xFFFF8E8E), Color(0xFFFF7A7A)],
                ),
              ),
              child: const Center(
                child: Text(
                  '수락',
                  style: TextStyle(
                    fontFamily: 'NotoSansKR',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: GestureDetector(
            onTap: () => onAction?.call(notification.id, false),
            child: Container(
              height: 34,
              decoration: BoxDecoration(
                color: const Color(0xFFF5F3F0),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Center(
                child: Text(
                  '거절',
                  style: TextStyle(
                    fontFamily: 'NotoSansKR',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF888888),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
