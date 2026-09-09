import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../common/widgets/app_bar_widget.dart';
import '../../../../common/widgets/primary_button.dart';

class TermsScreen extends StatefulWidget {
  const TermsScreen({super.key});

  @override
  State<TermsScreen> createState() => _TermsScreenState();
}

class _TermsScreenState extends State<TermsScreen> {
  bool _agreeAll = false;
  bool _agreeService = false;
  bool _agreePrivacy = false;

  bool get _canProceed => _agreeService && _agreePrivacy;

  void _onToggleAll(bool checked) {
    setState(() {
      _agreeAll = checked;
      _agreeService = checked;
      _agreePrivacy = checked;
    });
  }

  void _onToggle(String type, bool value) {
    setState(() {
      if (type == 'service') _agreeService = value;
      if (type == 'privacy') _agreePrivacy = value;
      _agreeAll = _agreeService && _agreePrivacy;
    });
  }

  void _onNext() {
    if (!_canProceed) return;
    context.go('/profile-setup');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            AppBarWidget(title: '약관 동의'),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '반가워요!\n시작 전 동의가 필요해요.',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textDark,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          _CheckRow(
                            label: '전체 동의하기',
                            value: _agreeAll,
                            onChanged: _onToggleAll,
                            isBold: true,
                            showDivider: true,
                          ),
                          _CheckRow(
                            label: '(필수) 서비스 이용약관',
                            value: _agreeService,
                            onChanged: (v) => _onToggle('service', v),
                            showDivider: true,
                          ),
                          _CheckRow(
                            label: '(필수) 개인정보 처리방침',
                            value: _agreePrivacy,
                            onChanged: (v) => _onToggle('privacy', v),
                            showDivider: false,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding:
                  const EdgeInsets.only(left: 24, right: 24, bottom: 34, top: 16),
              child: PrimaryButton(
                label: '다음으로',
                onTap: _canProceed ? _onNext : null,
                enabled: _canProceed,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool isBold;
  final bool showDivider;

  const _CheckRow({
    required this.label,
    required this.value,
    required this.onChanged,
    this.isBold = false,
    required this.showDivider,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            children: [
              GestureDetector(
                onTap: () => onChanged(!value),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: value ? AppColors.primaryLight : Colors.transparent,
                    border: Border.all(
                      color: value ? AppColors.primaryLight : AppColors.borderDisabled,
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: value
                      ? const Icon(Icons.check, size: 13, color: Colors.white)
                      : null,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                label,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: isBold ? FontWeight.bold : FontWeight.w300,
                  color: AppColors.textDark,
                ),
              ),
            ],
          ),
        ),
        if (showDivider)
          const Divider(
              height: 1,
              color: Color(0xFFF5F5F5),
              indent: 16,
              endIndent: 16),
      ],
    );
  }
}
