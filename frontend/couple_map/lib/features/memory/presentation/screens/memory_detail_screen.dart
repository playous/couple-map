import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../auth/domain/providers/auth_provider.dart';
import '../../data/models/memory_model.dart';
import '../../domain/providers/memory_provider.dart';
import '../widgets/audio_player_widget.dart';
import 'photo_gallery_screen.dart';
import 'video_player_screen.dart';

Future<bool?> showMemoryDetailSheet(BuildContext context, int mapId, int memoryId) {
  return showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'MemoryDetail',
    barrierColor: Colors.transparent,
    transitionDuration: Duration.zero,
    pageBuilder: (context, animation, secondaryAnimation) {
      return _MemoryDetailOverlay(mapId: mapId, memoryId: memoryId);
    },
  );
}

class _MemoryDetailOverlay extends ConsumerStatefulWidget {
  final int mapId;
  final int memoryId;

  const _MemoryDetailOverlay({required this.mapId, required this.memoryId});

  @override
  ConsumerState<_MemoryDetailOverlay> createState() => _MemoryDetailOverlayState();
}

class _MemoryDetailOverlayState extends ConsumerState<_MemoryDetailOverlay> {
  MemoryModel? _memory;
  bool _isLoading = true;
  double _sheetFraction = 0.6;

  @override
  void initState() {
    super.initState();
    _loadMemory();
  }

  Future<void> _loadMemory() async {
    final auth = ref.read(authProvider);
    if (auth is! AuthSuccess) return;
    try {
      final memory = await ref.read(memoryRepositoryProvider).getMemoryDetail(
        widget.mapId,
        widget.memoryId,
      );
      if (mounted) setState(() { _memory = memory; _isLoading = false; });
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteMemory() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('추억 삭제'),
        content: const Text('정말 삭제하시겠습니까?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final auth = ref.read(authProvider);
    if (auth is! AuthSuccess) return;
    try {
      await ref.read(memoryRepositoryProvider).deleteMemory(
        widget.mapId,
        widget.memoryId,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('삭제 실패: $e')),
        );
      }
    }
  }

  void _onHandleDrag(DragUpdateDetails details) {
    final screenHeight = MediaQuery.of(context).size.height;
    setState(() {
      _sheetFraction -= details.delta.dy / screenHeight;
      _sheetFraction = _sheetFraction.clamp(0.15, 0.9);
    });
  }

  void _onHandleDragEnd(DragEndDetails details) {
    // 너무 작으면 닫기
    if (_sheetFraction < 0.25) {
      Navigator.pop(context);
      return;
    }
    // 스냅: 0.6 또는 0.9
    setState(() {
      _sheetFraction = _sheetFraction < 0.75 ? 0.6 : 0.9;
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final sheetHeight = screenHeight * _sheetFraction;

    return Stack(
      children: [
        // 배경 블러 + 탭으로 닫기
        Positioned.fill(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(color: Colors.black.withValues(alpha: 0.3)),
            ),
          ),
        ),
        // 바텀 시트
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: sheetHeight,
          child: Container(
            decoration: const BoxDecoration(
              color: Color(0xFFFDFBF7),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              boxShadow: [
                BoxShadow(
                  color: Color(0x1A000000),
                  blurRadius: 20,
                  offset: Offset(0, -4),
                ),
              ],
            ),
            child: Column(
              children: [
                // 드래그 핸들
                GestureDetector(
                  onVerticalDragUpdate: _onHandleDrag,
                  onVerticalDragEnd: _onHandleDragEnd,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: const Color(0xFFDDD8D3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator(color: Color(0xFFFF7A7A)))
                      : _memory == null
                          ? const Center(child: Text('데이터를 불러올 수 없습니다'))
                          : _buildContent(_memory!),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildContent(MemoryModel memory) {
    final images = memory.mediaFiles.where((f) => f.fileType == MediaType.image).toList();
    final videos = memory.mediaFiles.where((f) => f.fileType == MediaType.video).toList();
    final audios = memory.mediaFiles.where((f) => f.fileType == MediaType.audio).toList();
    final mediaCount = images.length + videos.length;
    final dateStr = '${memory.memoryDate.year}.${memory.memoryDate.month.toString().padLeft(2, '0')}.${memory.memoryDate.day.toString().padLeft(2, '0')}';

    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 12, 20, MediaQuery.of(context).padding.bottom + 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 날짜 + 수정/삭제/닫기
            Row(
              children: [
                Text(
                  dateStr,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFFAAAAAA),
                    decoration: TextDecoration.none,
                  ),
                ),
                const Spacer(),
                _actionButton('수정', const Color(0xFF888888), const Color(0xFFF5F3F0), () {
                  Navigator.pop(context);
                  context.push('/map/${widget.mapId}/memory/${widget.memoryId}/edit');
                }),
                const SizedBox(width: 6),
                _actionButton('삭제', const Color(0xFFE05555), const Color(0xFFFFF0F0), _deleteMemory),
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0F0F0),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Center(
                      child: Text(
                        '✕',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF888888),
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 제목
            Text(
              memory.title,
              style: const TextStyle(
                fontFamily: 'NotoSerifKR',
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: Color(0xFF191919),
                letterSpacing: -0.5,
                decoration: TextDecoration.none,
              ),
            ),
            const SizedBox(height: 6),

            // 장소
            Row(
              children: [
                const Icon(Icons.place, size: 16, color: Color(0xFFFF7A7A)),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    memory.placeName,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF999999),
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
              ],
            ),

            // 사진 · 동영상
            if (mediaCount > 0) ...[
              const SizedBox(height: 20),
              Row(
                children: [
                  const Text(
                    '사진·동영상',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF888888),
                      decoration: TextDecoration.none,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F1F1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$mediaCount',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFAAAAAA),
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                ],
              ),
              _buildMediaGrid(images, videos),
            ],

            // 오디오
            if (audios.isNotEmpty) ...[
              const SizedBox(height: 20),
              Row(
                children: [
                  const Text(
                    '오디오',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF888888),
                      decoration: TextDecoration.none,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F1F1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${audios.length}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFAAAAAA),
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ...audios.map((a) => AudioPlayerWidget(audioUrl: a.fileUrl)),
            ],

            // 내용
            if (memory.content != null && memory.content!.isNotEmpty) ...[
              const SizedBox(height: 20),
              const Text(
                '메모',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF888888),
                  decoration: TextDecoration.none,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8F6F3),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFF0ECE8)),
                ),
                child: Text(
                  memory.content!,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF666666),
                    height: 1.6,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _actionButton(String label, Color textColor, Color bgColor, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: textColor,
            decoration: TextDecoration.none,
          ),
        ),
      ),
    );
  }

  Widget _buildMediaGrid(List<MediaFile> images, List<MediaFile> videos) {
    final allMedia = <_MediaItem>[];
    for (int i = 0; i < images.length; i++) {
      allMedia.add(_MediaItem(url: images[i].fileUrl, isVideo: false, imageIndex: i));
    }
    for (final vid in videos) {
      allMedia.add(_MediaItem(url: vid.fileUrl, isVideo: true));
    }

    return GridView.builder(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: 10),
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
        childAspectRatio: 1.0,
        mainAxisExtent: 110,
      ),
      itemCount: allMedia.length,
      itemBuilder: (context, index) {
        final item = allMedia[index];
        return GestureDetector(
          onTap: () {
            if (item.isVideo) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => VideoPlayerScreen(videoUrl: item.url),
                ),
              );
            } else {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PhotoGalleryScreen(
                    images: images,
                    initialIndex: item.imageIndex,
                  ),
                ),
              );
            }
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (item.isVideo)
                  Container(
                    color: const Color(0xFFD5E8D4),
                    child: const Center(
                      child: Icon(Icons.play_circle_fill, size: 36, color: Colors.white70),
                    ),
                  )
                else
                  Image.network(
                    item.url,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: const Color(0xFFF0ECE8),
                      child: const Icon(Icons.broken_image, color: Color(0xFFCCCCCC)),
                    ),
                  ),
                if (item.isVideo)
                  Positioned(
                    right: 6,
                    bottom: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        '동영상',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

}

class _MediaItem {
  final String url;
  final bool isVideo;
  final int imageIndex;
  const _MediaItem({required this.url, required this.isVideo, this.imageIndex = 0});
}
