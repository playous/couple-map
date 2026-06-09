import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../auth/domain/providers/auth_provider.dart';
import '../../../friend/data/repositories/friend_repository.dart';
import '../../../friend/domain/providers/friend_provider.dart';
import '../../domain/providers/map_provider.dart';

class MapInviteScreen extends ConsumerStatefulWidget {
  final int mapId;

  const MapInviteScreen({super.key, required this.mapId});

  @override
  ConsumerState<MapInviteScreen> createState() => _MapInviteScreenState();
}

class _MapInviteScreenState extends ConsumerState<MapInviteScreen> {
  List<FriendInfo> _friends = [];
  final Set<int> _invitedIds = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadFriends();
  }

  Future<void> _loadFriends() async {
    final auth = ref.read(authProvider);
    if (auth is! AuthSuccess) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    try {
      final friends = await ref.read(friendRepositoryProvider).getFriendList();
      if (mounted) setState(() { _friends = friends; _isLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _inviteFriend(int friendId) async {
    final auth = ref.read(authProvider);
    if (auth is! AuthSuccess) return;
    try {
      await ref.read(mapRepositoryProvider).inviteFriendToMap(widget.mapId, friendId);
      if (!mounted) return;
      setState(() => _invitedIds.add(friendId));
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('초대를 보냈어요!')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('오류: ${e.toString()}')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF191919)),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/');
            }
          },
        ),
        title: const Text(
          '친구 초대',
          style: TextStyle(
              color: Color(0xFF191919),
              fontSize: 18,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5),
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _friends.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.people_outline, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text('초대할 친구가 없어요',
                          style: TextStyle(color: Colors.grey, fontSize: 16)),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _friends.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final f = _friends[index];
                    final isInvited = _invitedIds.contains(f.id);
                    return Card(
                      elevation: 0,
                      color: Colors.grey[50],
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: const Color(0xFFFFE5E5),
                          backgroundImage: f.imageUrl != null
                              ? NetworkImage(f.imageUrl!)
                              : null,
                          child: f.imageUrl == null
                              ? Text(f.nickname[0],
                                  style: const TextStyle(
                                      color: Color(0xFFFF7A7A),
                                      fontWeight: FontWeight.w700))
                              : null,
                        ),
                        title: Text(f.nickname,
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: f.friendCode != null
                            ? Text('#${f.friendCode}',
                                style: const TextStyle(fontSize: 13))
                            : null,
                        trailing: TextButton(
                          onPressed:
                              isInvited ? null : () => _inviteFriend(f.id),
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFFFF7A7A),
                            disabledForegroundColor: Colors.grey,
                          ),
                          child: Text(isInvited ? '완료' : '초대'),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
