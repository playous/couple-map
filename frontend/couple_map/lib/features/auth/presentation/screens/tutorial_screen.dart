import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../common/widgets/primary_button.dart';

class TutorialScreen extends StatefulWidget {
  const TutorialScreen({super.key});

  @override
  State<TutorialScreen> createState() => _TutorialScreenState();
}

class _TutorialScreenState extends State<TutorialScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  static const _pages = [
    _TutorialData(
      emoji: '🗺️',
      title: '함께 만드는 우리만의 지도',
      description: '커플, 가족, 친구와 함께\n특별한 추억을 지도에 기록하세요',
    ),
    _TutorialData(
      emoji: '📍',
      title: '추억을 기록하세요',
      description: '장소를 검색하고, 사진과 메모를 남겨\n소중한 순간을 영원히 간직하세요',
    ),
  ];

  void _onNext() {
    if (_currentPage < _pages.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _goToTerms();
    }
  }

  void _goToTerms() {
    context.go('/terms');
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: (index) =>
                    setState(() => _currentPage = index),
                itemCount: _pages.length,
                itemBuilder: (context, index) =>
                    _TutorialPage(data: _pages[index]),
              ),
            ),
            _PageIndicator(
                currentPage: _currentPage, totalPages: _pages.length),
            const SizedBox(height: 28),
            Padding(
              padding:
                  const EdgeInsets.only(left: 24, right: 24, bottom: 34),
              child: Column(
                children: [
                  PrimaryButton(
                    label: _currentPage < _pages.length - 1 ? '다음' : '시작하기',
                    onTap: _onNext,
                  ),
                  const SizedBox(height: 10),
                  GestureDetector(
                    onTap: _goToTerms,
                    child: Container(
                      width: double.infinity,
                      height: 52,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.border),
                      ),
                      alignment: Alignment.center,
                      child: const Text(
                        '건너뛰기',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textDark,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TutorialData {
  final String emoji;
  final String title;
  final String description;

  const _TutorialData({
    required this.emoji,
    required this.title,
    required this.description,
  });
}

class _TutorialPage extends StatelessWidget {
  final _TutorialData data;

  const _TutorialPage({required this.data});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(data.emoji, style: const TextStyle(fontSize: 80)),
          const SizedBox(height: 30),
          Text(
            data.title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            data.description,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w300,
              color: AppColors.textGray,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}

class _PageIndicator extends StatelessWidget {
  final int currentPage;
  final int totalPages;

  const _PageIndicator({required this.currentPage, required this.totalPages});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(totalPages, (index) {
        final isActive = index == currentPage;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: isActive ? 24 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: isActive ? AppColors.primaryLight : AppColors.borderDisabled,
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }
}
