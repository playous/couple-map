import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/data/models/user_model.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/tutorial_screen.dart';
import '../../features/auth/presentation/screens/terms_screen.dart';
import '../../features/auth/presentation/screens/profile_setup_screen.dart';
import '../../features/home/presentation/screens/home_screen.dart';
import '../../features/notification/presentation/screens/notification_screen.dart';
import '../../features/map/presentation/screens/map_create_screen.dart';
import '../../features/map/presentation/screens/map_detail_screen.dart';
import '../../features/map/presentation/screens/map_settings_screen.dart';
import '../../features/map/presentation/screens/map_invite_screen.dart';
import '../../features/map/presentation/screens/map_member_list_screen.dart';
import '../../features/map/presentation/screens/place_search_screen.dart';
import '../../features/memory/presentation/screens/memory_create_screen.dart';
import '../../features/memory/presentation/screens/memory_edit_screen.dart';
import '../../features/memory/presentation/screens/memory_list_screen.dart';
import '../../features/map/presentation/screens/map_edit_screen.dart';
import '../../features/mypage/presentation/screens/profile_edit_screen.dart';
import '../../features/friend/presentation/screens/friend_screen.dart';

final _storage = const FlutterSecureStorage();

/// 인증 플로우에서 리다이렉트 하면 안 되는 경로들
const _authFlowPaths = ['/login', '/tutorial', '/terms', '/profile-setup'];

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/login',
    redirect: (context, state) async {
      final token = await _storage.read(key: 'accessToken');
      final currentPath = state.matchedLocation;
      final isAuthFlow = _authFlowPaths.contains(currentPath);
      final isLoggedIn = token != null && token.isNotEmpty;

      if (!isLoggedIn && !isAuthFlow) return '/login';
      if (isLoggedIn && currentPath == '/login') return '/home';
      return null;
    },
    routes: [
      // ── 인증 플로우 ──
      GoRoute(
        path: '/login',
        builder: (_, __) => const LoginScreen(),
      ),
      GoRoute(
        path: '/tutorial',
        builder: (_, __) => const TutorialScreen(),
      ),
      GoRoute(
        path: '/terms',
        builder: (_, __) => const TermsScreen(),
      ),
      GoRoute(
        path: '/profile-setup',
        builder: (_, __) => const ProfileSetupScreen(),
      ),

      // ── 홈 ──
      GoRoute(
        path: '/home',
        builder: (_, __) => const HomeScreen(),
      ),

      // ── 알림 ──
      GoRoute(
        path: '/notifications',
        builder: (_, __) => const NotificationScreen(),
      ),

      // ── 지도 ──
      GoRoute(
        path: '/map/create',
        builder: (_, __) => const MapCreateScreen(),
      ),
      GoRoute(
        path: '/map/:mapId',
        builder: (_, state) {
          final mapId = int.parse(state.pathParameters['mapId']!);
          final extra = state.extra as Map<String, dynamic>?;
          return MapDetailScreen(
            mapId: mapId,
            mapName: extra?['mapName'] as String?,
            description: extra?['description'] as String?,
            memberCount: extra?['memberCount'] as int? ?? 1,
            category: extra?['category'] as String?,
          );
        },
        routes: [
          GoRoute(
            path: 'settings',
            builder: (_, state) {
              final mapId = int.parse(state.pathParameters['mapId']!);
              final extra = state.extra as Map<String, dynamic>;
              return MapSettingsScreen(
                mapId: mapId,
                mapName: extra['mapName'] as String,
                description: extra['description'] as String?,
                memberCount: extra['memberCount'] as int? ?? 1,
                category: extra['category'] as String?,
              );
            },
          ),
          GoRoute(
            path: 'edit',
            builder: (_, state) {
              final mapId = int.parse(state.pathParameters['mapId']!);
              return MapEditScreen(mapId: mapId);
            },
          ),
          GoRoute(
            path: 'memories',
            builder: (_, state) {
              final mapId = int.parse(state.pathParameters['mapId']!);
              return MemoryListScreen(mapId: mapId);
            },
          ),
          GoRoute(
            path: 'members',
            builder: (_, state) {
              final mapId = int.parse(state.pathParameters['mapId']!);
              return MapMemberListScreen(mapId: mapId);
            },
          ),
          GoRoute(
            path: 'invite',
            builder: (_, state) {
              final mapId = int.parse(state.pathParameters['mapId']!);
              return MapInviteScreen(mapId: mapId);
            },
          ),
          GoRoute(
            path: 'memory/create',
            builder: (_, state) {
              final mapId = int.parse(state.pathParameters['mapId']!);
              final extra = state.extra as Map<String, dynamic>?;
              return MemoryCreateScreen(
                mapId: mapId,
                placeName: extra?['placeName'] as String?,
                address: extra?['addressName'] as String?,
                latitude: extra?['latitude'] as double?,
                longitude: extra?['longitude'] as double?,
              );
            },
          ),
          GoRoute(
            path: 'memory/:memoryId',
            builder: (_, __) => const SizedBox.shrink(),
            routes: [
              GoRoute(
                path: 'edit',
                builder: (_, state) {
                  final mapId = int.parse(state.pathParameters['mapId']!);
                  final memoryId = int.parse(state.pathParameters['memoryId']!);
                  return MemoryEditScreen(mapId: mapId, memoryId: memoryId);
                },
              ),
            ],
          ),
        ],
      ),

      // ── 장소 검색 ──
      GoRoute(
        path: '/place-search',
        builder: (_, __) => const PlaceSearchScreen(),
      ),

      // ── 프로필 수정 ──
      GoRoute(
        path: '/profile/edit',
        builder: (_, state) => ProfileEditScreen(
          user: state.extra as UserModel,
        ),
      ),

      // ── 친구 ──
      GoRoute(
        path: '/friends',
        builder: (_, __) => const FriendScreen(),
      ),
    ],
    errorBuilder: (_, state) => Scaffold(
      body: Center(child: Text('페이지를 찾을 수 없어요: ${state.error}')),
    ),
  );
});
