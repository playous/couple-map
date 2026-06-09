import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../auth/domain/providers/auth_provider.dart';
import '../../../auth/data/models/user_model.dart';
import '../../../friend/domain/providers/friend_provider.dart';
import '../../domain/providers/mypage_provider.dart';
import '../../../home/domain/providers/home_provider.dart';

class MypageScreen extends ConsumerStatefulWidget {
  final VoidCallback? onLogout;

  const MypageScreen({super.key, this.onLogout});

  @override
  ConsumerState<MypageScreen> createState() => MypageScreenState();
}

class MypageScreenState extends ConsumerState<MypageScreen> {
  UserModel? _user;
  int _mapCount = 0;
  int _friendCount = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<String?> _getToken() async {
    final auth = ref.read(authProvider);
    if (auth is AuthSuccess) return auth.token.accessToken;
    return await ref.read(authRepositoryProvider).getAccessToken();
  }

  void loadData() => _loadData();

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final token = await _getToken();
      if (token == null) return;

      final results = await Future.wait([
        ref.read(mypageRepositoryProvider).getUserInfo(),
        ref.read(homeRepositoryProvider).getMapList(),
        ref.read(friendRepositoryProvider).getFriendList(),
      ]);

      if (mounted) {
        setState(() {
          _user = results[0] as UserModel;
          _mapCount = (results[1] as List).length;
          _friendCount = (results[2] as List).length;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _logout() async {
    try {
      await ref.read(authRepositoryProvider).logout();
    } catch (_) {}
    ref.read(authProvider.notifier).reset();
    widget.onLogout?.call();
  }

  Future<void> _deleteAccount() async {
    // 1차 확인
    final firstConfirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFFFDFBF7),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          '회원 탈퇴',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        content: const Text('탈퇴하면 모든 데이터가 삭제되며\n복구할 수 없어요. 정말 탈퇴하시겠어요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소', style: TextStyle(color: Color(0xFF888888))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('탈퇴', style: TextStyle(color: Color(0xFFD32F2F), fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (firstConfirm != true || !mounted) return;

    // 2차 확인
    final secondConfirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFFFDFBF7),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          '정말 탈퇴하시겠어요?',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        content: const Text('지도, 추억, 친구 목록 등\n모든 정보가 영구적으로 삭제됩니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소', style: TextStyle(color: Color(0xFF888888))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('탈퇴하기', style: TextStyle(color: Color(0xFFD32F2F), fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (secondConfirm != true) return;

    try {
      await ref.read(mypageRepositoryProvider).deleteAccount();
      await ref.read(authRepositoryProvider).clearToken();
    } catch (_) {}
    if (mounted) {
      ref.read(authProvider.notifier).reset();
      widget.onLogout?.call();
    }
  }

  void _copyCode(String code) {
    Clipboard.setData(ClipboardData(text: code));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFDFBF7),
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFFFF8E8E)),
                  )
                : _user == null
                    ? const Center(child: Text('정보를 불러올 수 없어요'))
                    : _buildBody(_user!),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return SafeArea(
      bottom: false,
      child: Container(
        color: const Color(0xFFFDFBF7),
        padding: const EdgeInsets.fromLTRB(0, 10, 0, 14),
        child: const Center(
          child: Text(
            '마이페이지',
            style: TextStyle(
              fontFamily: 'NotoSansKR',
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: Color(0xFF2C2C2C),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(UserModel user) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          _buildProfileCard(user),
          const SizedBox(height: 12),
          _buildStatsRow(),
          const SizedBox(height: 12),
          _buildMenuSection1(user),
          const SizedBox(height: 12),
          _buildMenuSection2(),
          const SizedBox(height: 12),
          _buildLogoutSection(),
          const SizedBox(height: 24),
          Center(
            child: GestureDetector(
              onTap: _deleteAccount,
              child: const Text(
                '회원 탈퇴',
                style: TextStyle(
                  color: Color(0xFFBBBBBB),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildProfileCard(UserModel user) {
    return Container(
      width: double.infinity,
      height: 192,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(color: Color(0x0D000000), blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 아바타
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: user.profileImageUrl == null
                  ? const [
                      Color(0xFFFFE5E5),
                      Color(0xFFE5F0FF),
                      Color(0xFFE5FFE8),
                      Color(0xFFFFF3E5),
                      Color(0xFFF0E5FF),
                    ][user.userId % 5]
                  : const Color(0xFFFFE4E1),
              borderRadius: BorderRadius.circular(40),
            ),
            child: Center(
              child: user.profileImageUrl != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(40),
                      child: Image.network(
                        user.profileImageUrl!,
                        width: 80,
                        height: 80,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Text(
                          const ['🐰', '🦊', '🐶', '🐼', '🐻'][user.userId % 5],
                          style: const TextStyle(fontSize: 36),
                        ),
                      ),
                    )
                  : Text(
                      const ['🐰', '🦊', '🐶', '🐼', '🐻'][user.userId % 5],
                      style: const TextStyle(fontSize: 36),
                    ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            user.nickname,
            style: const TextStyle(
              fontFamily: 'NotoSansKR',
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: Color(0xFF2C2C2C),
            ),
          ),
          const SizedBox(height: 4),
          GestureDetector(
            onTap: () => _copyCode(user.friendCode),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  user.friendCode,
                  style: const TextStyle(
                    fontFamily: 'NotoSansKR',
                    fontSize: 13,
                    fontWeight: FontWeight.w300,
                    color: Color(0xFF888888),
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.copy, size: 12, color: Color(0xFFCCCCCC)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsRow() {
    return Row(
      children: [
        _StatCard(value: _user?.memoryCount.toString() ?? '0', label: '추억'),
        const SizedBox(width: 10),
        _StatCard(value: _mapCount.toString(), label: '지도'),
        const SizedBox(width: 10),
        _StatCard(value: _friendCount.toString(), label: '친구'),
      ],
    );
  }

  Widget _buildMenuSection1(UserModel user) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(color: Color(0x0D000000), blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        children: [
          _MenuRow(
            label: '프로필 수정',
            hasBorder: true,
            onTap: () async {
              final result = await context.push<Map<String, dynamic>>('/profile/edit', extra: user);
              if (result != null && mounted) {
                setState(() {
                  _user = _user!.copyWith(
                    nickname: result['nickname'] as String?,
                    profileImageUrl: result['profileImageUrl'] as String?,
                  );
                });
              }
            },
          ),
          _MenuRow(
            label: '친구 관리',
            hasBorder: true,
            onTap: () => context.push('/friends')
                .then((_) => _loadData()),
          ),
          _MenuRow(label: '알림 설정', hasBorder: false, onTap: null),
        ],
      ),
    );
  }

  Widget _buildMenuSection2() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(color: Color(0x0D000000), blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: const Column(
        children: [
          _MenuRow(label: '이용약관', hasBorder: true),
          _MenuRow(label: '개인정보 처리방침', hasBorder: true),
          _MenuRow(label: '버전 정보', trailing: 'v1.0.0', hasBorder: false),
        ],
      ),
    );
  }

  Widget _buildLogoutSection() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(color: Color(0x0D000000), blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: _MenuRow(
        label: '로그아웃',
        labelColor: const Color(0xFFD32F2F),
        hasBorder: false,
        onTap: _logout,
      ),
    );
  }
}

// ─────────────────────────────────────────────
// 통계 카드
// ─────────────────────────────────────────────
class _StatCard extends StatelessWidget {
  final String value;
  final String label;

  const _StatCard({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        height: 65,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(color: Color(0x0D000000), blurRadius: 8, offset: Offset(0, 2)),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              value,
              style: const TextStyle(
                fontFamily: 'Gaegu',
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Color(0xFFFF8E8E),
                height: 1,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                fontFamily: 'NotoSansKR',
                fontSize: 11,
                fontWeight: FontWeight.w300,
                color: Color(0xFF888888),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// 메뉴 행
// ─────────────────────────────────────────────
class _MenuRow extends StatelessWidget {
  final String label;
  final Color? labelColor;
  final String? trailing;
  final VoidCallback? onTap;
  final bool hasBorder;

  const _MenuRow({
    required this.label,
    this.labelColor,
    this.trailing,
    this.onTap,
    required this.hasBorder,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: hasBorder
            ? const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Color(0xFFF5F2EE)),
                ),
              )
            : null,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                fontFamily: 'NotoSansKR',
                fontSize: 15,
                fontWeight: FontWeight.w300,
                color: labelColor ?? const Color(0xFF2C2C2C),
              ),
            ),
            trailing != null
                ? Text(
                    trailing!,
                    style: const TextStyle(
                      fontFamily: 'NotoSansKR',
                      fontSize: 13,
                      fontWeight: FontWeight.w300,
                      color: Color(0xFF888888),
                    ),
                  )
                : const Text(
                    '›',
                    style: TextStyle(fontSize: 15, color: Color(0xFFCCCCCC)),
                  ),
          ],
        ),
      ),
    );
  }
}
