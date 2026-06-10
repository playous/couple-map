import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/providers/auth_provider.dart';
import '../widgets/social_login_button.dart';

class LoginScreen extends ConsumerWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final notifier = ref.read(authProvider.notifier);

    // 로그인 성공 시 화면 이동
    ref.listen(authProvider, (_, next) {
      if (next is AuthSuccess) {
        final token = next.token;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!context.mounted) return;
          if (token.nicknameSet) {
            context.go('/home');
          } else {
            context.push('/tutorial');
          }
        });
      } else if (next is AuthError) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!context.mounted) return;
          _showErrorDialog(context, next.message, ref);
        });
      }
    });

    final isLoading = authState is AuthLoading;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // 로고 영역
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Vestige',
                      style: TextStyle(
                        fontFamily: 'Gaegu',
                        fontSize: 52,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '우리 둘만의 추억을\n지도에 기록해보세요',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w300,
                        color: AppColors.textGray,
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        '암호화된 안전한 공간',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w300,
                          color: AppColors.textGray,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // 소셜 로그인 버튼
            Padding(
              padding: const EdgeInsets.only(
                  left: 50, right: 50, bottom: 34, top: 16),
              child: isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                        strokeWidth: 3,
                      ),
                    )
                  : Column(
                      children: [
                        SocialLoginButton.kakao(
                            onTap: notifier.loginWithKakao),
                        const SizedBox(height: 12),
                        SocialLoginButton.naver(
                            onTap: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('네이버 로그인은 아직 지원하지 않습니다.'),
                                ),
                              );
                            }),
                        const SizedBox(height: 12),
                        SocialLoginButton.google(
                            onTap: notifier.loginWithGoogle),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _showErrorDialog(BuildContext context, String message, WidgetRef ref) {
    ref.read(authProvider.notifier).reset();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('오류',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20)),
        content: Text(message,
            style: const TextStyle(fontSize: 15, height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('확인',
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    color: AppColors.primary)),
          ),
        ],
      ),
    );
  }
}
