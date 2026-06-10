import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import '../../../auth/domain/providers/auth_provider.dart';
import '../../../auth/data/models/user_model.dart';
import '../../../mypage/domain/providers/mypage_provider.dart';
import '../../data/models/map_card_model.dart';
import '../../domain/providers/home_provider.dart';
import '../../../mypage/presentation/screens/mypage_screen.dart';
import '../../../calendar/presentation/screens/calendar_screen.dart';
import '../widgets/map_card_widget.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _mypageKey = GlobalKey<MypageScreenState>();
  int _currentIndex = 0;
  UserModel? _userInfo;
  List<MapCardModel> _mapList = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
    _requestMediaPermissions();
  }

  Future<void> _requestMediaPermissions() async {
    try {
      if (Platform.isAndroid) {
        await [Permission.photos, Permission.videos, Permission.audio].request();
      } else if (Platform.isIOS) {
        await Permission.photos.request();
      }
    } catch (e) {
      debugPrint('권한 요청 실패 (무시됨): $e');
    }
  }

  Future<String?> _getToken() async {
    final authState = ref.read(authProvider);
    if (authState is AuthSuccess) return authState.token.accessToken;
    return await ref.read(authRepositoryProvider).getAccessToken();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final token = await _getToken();
      if (token == null) throw '로그인 정보가 없습니다.';

      final results = await Future.wait([
        ref.read(mypageRepositoryProvider).getUserInfo(),
        ref.read(homeRepositoryProvider).getMapList(),
      ]);

      if (mounted) {
        setState(() {
          _userInfo = results[0] as UserModel;
          _mapList = results[1] as List<MapCardModel>;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '홈 화면 정보를 불러오지 못했어요. 잠시 후 다시 시도해주세요.';
          _isLoading = false;
        });
      }
    }
  }

  void _openNotifications() {
    context.push('/notifications');
  }

  Future<void> _openMapCreate() async {
    final result = await context.push('/map/create');
    if (!mounted) return;
    if (result != null) _loadData();
  }

  void _handleLogout() {
    context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFDFBF7),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          _buildMapListPage(),
          const CalendarScreen(),
          MypageScreen(key: _mypageKey, onLogout: _handleLogout),
        ],
      ),
      floatingActionButton: _currentIndex == 0 ? _buildFab() : null,
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  // ── 지도 목록 탭 ──
  Widget _buildMapListPage() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFFFF8E8E)),
      );
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _error!,
              style: const TextStyle(color: Color(0xFF888888)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: _loadData,
              child: const Text(
                '다시 시도',
                style: TextStyle(color: Color(0xFFFF8E8E)),
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      color: const Color(0xFFFF8E8E),
      onRefresh: _loadData,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _buildHeader()),
          if (_mapList.isEmpty)
            SliverFillRemaining(child: _buildEmptyState())
          else ...[
            SliverToBoxAdapter(child: _buildDDayBanner()),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, i) => Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: MapCardWidget(
                      map: _mapList[i],
                      onTap: () => context.push(
                        '/map/${_mapList[i].mapId}',
                        extra: {
                          'mapName': _mapList[i].mapName,
                          'description': _mapList[i].description,
                          'memberCount': _mapList[i].memberCount,
                          'category': _mapList[i].category,
                        },
                      ).then((_) => _loadData()),
                    ),
                  ),
                  childCount: _mapList.length,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 10, 24, 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Vestige',
              style: TextStyle(
                fontFamily: 'Gaegu',
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Color(0xFF2C2C2C),
              ),
            ),
            GestureDetector(
              onTap: _openNotifications,
              child: const Text('🔔', style: TextStyle(fontSize: 20)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDDayBanner() {
    final dDays = _userInfo?.dDays ?? 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
      child: Column(
        children: [
          const Text(
            '나의 기록이 시작된 지',
            style: TextStyle(
              fontFamily: 'NotoSansKR',
              fontSize: 13,
              fontWeight: FontWeight.w300,
              color: Color(0xFF888888),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'D+$dDays',
            style: const TextStyle(
              fontFamily: 'NotoSerifKR',
              fontSize: 40,
              fontWeight: FontWeight.bold,
              color: Color(0xFF2C2C2C),
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            '당신의 모든 순간을 기억해요',
            style: TextStyle(
              fontFamily: 'NotoSansKR',
              fontSize: 13,
              fontWeight: FontWeight.w300,
              color: Color(0xFFADB5BD),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Opacity(
            opacity: 0.25,
            child: const Text('🗺️', style: TextStyle(fontSize: 56)),
          ),
          const SizedBox(height: 16),
          const Text(
            '새로운 여정을 시작해보세요',
            style: TextStyle(
              fontFamily: 'NotoSansKR',
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: Color(0xFF2C2C2C),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '지도를 만들고\n추억을 기록할 수 있어요',
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

  // ── FAB ──
  Widget _buildFab() {
    return GestureDetector(
      onTap: _openMapCreate,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: const Color(0xFF2C2C2C),
          borderRadius: BorderRadius.circular(28),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1F000000),
              blurRadius: 24,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: const Center(
          child: Text(
            '+',
            style: TextStyle(
              fontFamily: 'NotoSansKR',
              fontSize: 28,
              color: Colors.white,
              fontWeight: FontWeight.w300,
            ),
          ),
        ),
      ),
    );
  }

  // ── 하단 네비게이션 ──
  Widget _buildBottomNav() {
    const items = [
      ('🏠', '홈'),
      ('📅', '캘린더'),
      ('👤', '마이'),
    ];
    return SafeArea(
      top: false,
      child: Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0x0D000000), width: 1)),
      ),
      child: SizedBox(
        height: 64,
        child: Row(
        children: List.generate(items.length, (i) {
          final isActive = i == _currentIndex;
          final color =
              isActive ? const Color(0xFF2C2C2C) : const Color(0xFFCCCCCC);
          return Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() => _currentIndex = i);
                if (i == 2) _mypageKey.currentState?.loadData();
              },
              behavior: HitTestBehavior.opaque,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(items[i].$1, style: const TextStyle(fontSize: 22)),
                  const SizedBox(height: 4),
                  Text(
                    items[i].$2,
                    style: TextStyle(
                      fontFamily: 'NotoSansKR',
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
        ),
      ),
      ),
    );
  }
}
