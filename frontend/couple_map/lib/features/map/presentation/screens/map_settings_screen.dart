import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../auth/domain/providers/auth_provider.dart';
import '../../domain/providers/map_provider.dart';


class MapSettingsScreen extends ConsumerStatefulWidget {
  final int mapId;
  final String mapName;
  final String? description;
  final int memberCount;
  final String? category;

  const MapSettingsScreen({
    super.key,
    required this.mapId,
    required this.mapName,
    this.description,
    this.memberCount = 1,
    this.category,
  });

  @override
  ConsumerState<MapSettingsScreen> createState() => _MapSettingsScreenState();
}

class _MapSettingsScreenState extends ConsumerState<MapSettingsScreen> {
  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          '지도 삭제',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        content: const Text('이 지도를 삭제하면 복구할 수 없어요.\n정말 삭제할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소', style: TextStyle(color: Color(0xFF888888))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              '삭제',
              style: TextStyle(color: Color(0xFFFF7A7A), fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final auth = ref.read(authProvider);
    if (auth is! AuthSuccess) return;
    try {
      await ref.read(mapRepositoryProvider).deleteMap(widget.mapId);
      if (mounted) context.go('/home');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('삭제 실패: ${e.toString()}')));
      }
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
          '지도 설정',
          style: TextStyle(
            color: Color(0xFF191919),
            fontSize: 18,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
        ),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: () => context.push('/map/${widget.mapId}/edit'),
            child: const Text(
              '수정',
              style: TextStyle(
                color: Color(0xFFFF7A7A),
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 기본 정보 섹션
            _buildSectionLabel('기본 정보'),
            const SizedBox(height: 8),
            _buildInfoCard([
              _buildInfoRow(
                label: '지도 이름',
                value: widget.mapName,
              ),
              _buildDivider(),
              _buildInfoRow(
                label: '설명',
                value: widget.description ?? '-',
              ),
            ]),

            const SizedBox(height: 28),

            // 멤버 관리 섹션
            _buildSectionLabel('멤버 관리'),
            const SizedBox(height: 8),
            _buildInfoCard([
              _buildNavRow(
                label: '참여 멤버',
                trailing: '${widget.memberCount}명',
                onTap: () => context.push('/map/${widget.mapId}/members'),
              ),
              _buildDivider(),
              _buildNavRow(
                label: '친구 초대',
                onTap: () => context.push('/map/${widget.mapId}/invite'),
              ),
            ]),

            const SizedBox(height: 40),

            // 지도 삭제
            Center(
              child: GestureDetector(
                onTap: _confirmDelete,
                child: const Text(
                  '지도 삭제하기',
                  style: TextStyle(
                    color: Color(0xFFBBBBBB),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionLabel(String label) {
    return Text(
      label,
      style: const TextStyle(
        color: Color(0xFF888888),
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  Widget _buildInfoCard(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(children: children),
    );
  }

  Widget _buildDivider() {
    return const Divider(height: 1, indent: 16, endIndent: 16, color: Color(0xFFF2F0EC));
  }

  Widget _buildInfoRow({
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 15,
                color: Color(0xFF191919),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF888888),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavRow({
    required String label,
    String? trailing,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 15,
                  color: Color(0xFF191919),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (trailing != null)
              Text(
                trailing,
                style: const TextStyle(fontSize: 14, color: Color(0xFF888888)),
              ),
            const SizedBox(width: 4),
            const Icon(Icons.arrow_forward_ios, size: 14, color: Color(0xFFBBBBBB)),
          ],
        ),
      ),
    );
  }
}
