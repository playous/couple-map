import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../auth/domain/providers/auth_provider.dart';
import '../../data/models/map_model.dart';
import '../../domain/providers/map_provider.dart';

class MapMemberListScreen extends ConsumerStatefulWidget {
  final int mapId;

  const MapMemberListScreen({super.key, required this.mapId});

  @override
  ConsumerState<MapMemberListScreen> createState() => _MapMemberListScreenState();
}

class _MapMemberListScreenState extends ConsumerState<MapMemberListScreen> {
  List<MapMemberInfo> _members = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  Future<void> _loadMembers() async {
    final auth = ref.read(authProvider);
    if (auth is! AuthSuccess) return;
    try {
      final members = await ref.read(mapRepositoryProvider).getMapMembers(
        widget.mapId,
      );
      if (mounted) setState(() { _members = members; _isLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _roleLabel(String role) {
    switch (role) {
      case 'OWNER':
        return 'Owner';
      case 'EDITOR':
        return '멤버';
      default:
        return role;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFDFBF7),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFDFBF7),
        elevation: 0,
        surfaceTintColor: const Color(0xFFFDFBF7),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Color(0xFF191919), size: 20),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          '참여 멤버',
          style: TextStyle(
            color: Color(0xFF191919),
            fontSize: 18,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFFF7A7A)))
          : _members.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.people_outline, size: 64, color: Color(0xFFBBBBBB)),
                      SizedBox(height: 16),
                      Text('멤버가 없어요', style: TextStyle(color: Color(0xFF888888), fontSize: 16)),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(20),
                  itemCount: _members.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final m = _members[index];
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 22,
                            backgroundColor: m.profileImageUrl == null
                                ? const [
                                    Color(0xFFFFE5E5),
                                    Color(0xFFE5F0FF),
                                    Color(0xFFE5FFE8),
                                    Color(0xFFFFF3E5),
                                    Color(0xFFF0E5FF),
                                  ][m.userId % 5]
                                : const Color(0xFFFFE5E5),
                            backgroundImage: m.profileImageUrl != null
                                ? NetworkImage(m.profileImageUrl!)
                                : null,
                            child: m.profileImageUrl == null
                                ? Text(
                                    const ['🐰', '🦊', '🐶', '🐼', '🐻'][m.userId % 5],
                                    style: const TextStyle(fontSize: 20),
                                  )
                                : null,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              m.nickname,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF191919),
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: m.role == 'OWNER'
                                  ? const Color(0xFFFFE5E5)
                                  : const Color(0xFFF2F0EC),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _roleLabel(m.role),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: m.role == 'OWNER'
                                    ? const Color(0xFFFF7A7A)
                                    : const Color(0xFF888888),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
