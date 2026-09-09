import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../common/widgets/app_bar_widget.dart';
import '../../../../common/widgets/primary_button.dart';
import '../../domain/providers/auth_provider.dart';

class ProfileSetupScreen extends ConsumerStatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  ConsumerState<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends ConsumerState<ProfileSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nicknameController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _nicknameController.dispose();
    super.dispose();
  }

  String? _validateNickname(String? value) {
    if (value == null || value.isEmpty) return '닉네임을 입력해주세요';
    if (value.length < 2 || value.length > 10) return '닉네임은 2-10자로 입력해주세요';
    final regex = RegExp(r'^[가-힣a-zA-Z0-9]+$');
    if (!regex.hasMatch(value)) return '한글, 영문, 숫자만 사용 가능합니다';
    return null;
  }

  Future<void> _setNickname() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      await ref
          .read(authRepositoryProvider)
          .setNickname(_nicknameController.text.trim());
      if (mounted) {
        context.go('/home');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString(),
                style: const TextStyle(fontWeight: FontWeight.w600)),
            backgroundColor: AppColors.primary,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            AppBarWidget(title: '프로필 설정'),
            Expanded(
              child: Form(
                key: _formKey,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      const SizedBox(height: 30),
                      // 프로필 아바타
                      Stack(
                        children: [
                          Container(
                            width: 100,
                            height: 100,
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFE4E1),
                              borderRadius: BorderRadius.circular(50),
                            ),
                            child: const Center(
                              child:
                                  Text('🐻', style: TextStyle(fontSize: 38)),
                            ),
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                color: AppColors.textDark,
                                borderRadius: BorderRadius.circular(15),
                                border: Border.all(
                                    color: AppColors.background, width: 2),
                              ),
                              child: const Center(
                                child: Text('📷',
                                    style: TextStyle(fontSize: 13)),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 40),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '닉네임',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[600],
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _nicknameController,
                        validator: _validateNickname,
                        maxLength: 10,
                        style: const TextStyle(
                          fontSize: 15,
                          color: AppColors.textDark,
                        ),
                        decoration: InputDecoration(
                          hintText: '사랑꾼',
                          hintStyle:
                              const TextStyle(color: AppColors.textLight),
                          filled: true,
                          fillColor: const Color(0xFFFAF8F5),
                          counterText: '',
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 17, vertical: 15),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide:
                                const BorderSide(color: AppColors.border),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide:
                                const BorderSide(color: AppColors.border),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(
                                color: AppColors.primaryLight, width: 1.5),
                          ),
                          errorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide:
                                const BorderSide(color: AppColors.primary),
                          ),
                          focusedErrorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(
                                color: AppColors.primary, width: 1.5),
                          ),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 10),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '2~10자의 한글, 영문, 숫자를 사용해요.',
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
            ),
            Padding(
              padding: const EdgeInsets.only(
                  left: 24, right: 24, bottom: 34, top: 16),
              child: PrimaryButton(
                label: '커플 맵 시작하기',
                onTap: _setNickname,
                isLoading: _isLoading,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
