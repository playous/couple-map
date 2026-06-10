import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../auth/domain/providers/auth_provider.dart';
import '../../data/models/memory_model.dart';
import '../../domain/providers/memory_provider.dart';
import 'memory_detail_screen.dart';

class MemoryListScreen extends ConsumerStatefulWidget {
  final int mapId;

  const MemoryListScreen({super.key, required this.mapId});

  @override
  ConsumerState<MemoryListScreen> createState() => _MemoryListScreenState();
}

class _MemoryListScreenState extends ConsumerState<MemoryListScreen> {
  List<MemorySummary> _memories = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasNext = true;
  int _currentPage = 0;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadMemories();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200
        && !_isLoadingMore
        && _hasNext) {
      _loadMore();
    }
  }

  Future<void> _loadMemories() async {
    final auth = ref.read(authProvider);
    if (auth is! AuthSuccess) return;
    try {
      final result = await ref
          .read(memoryRepositoryProvider)
          .getMemoryList(widget.mapId, page: 0);
      if (mounted) {
        setState(() {
          _memories = result.items;
          _hasNext = result.hasNext;
          _currentPage = 0;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMore() async {
    final auth = ref.read(authProvider);
    if (auth is! AuthSuccess) return;
    setState(() => _isLoadingMore = true);
    try {
      final result = await ref
          .read(memoryRepositoryProvider)
          .getMemoryList(widget.mapId, page: _currentPage + 1);
      if (mounted) {
        setState(() {
          _memories.addAll(result.items);
          _hasNext = result.hasNext;
          _currentPage += 1;
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF8F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFAF8F5),
        elevation: 0,
        surfaceTintColor: const Color(0xFFFAF8F5),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Color(0xFF191919), size: 20),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          '추억 목록',
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
          : _memories.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  color: const Color(0xFFFF7A7A),
                  onRefresh: _loadMemories,
                  child: ListView.separated(
                    controller: _scrollController,
                    padding: EdgeInsets.fromLTRB(20, 12, 20, MediaQuery.of(context).padding.bottom + 40),
                    itemCount: _memories.length + (_isLoadingMore ? 1 : 0),
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      if (index == _memories.length) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: CircularProgressIndicator(color: Color(0xFFFF7A7A)),
                          ),
                        );
                      }
                      return _buildMemoryCard(_memories[index]);
                    },
                  ),
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.photo_library_outlined, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            '저장된 추억이 없습니다',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '장소를 검색하여 추억을 만들어보세요',
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  Widget _buildMemoryCard(MemorySummary memory) {
    final dateStr = memory.memoryDate != null
        ? '${memory.memoryDate!.year}.${memory.memoryDate!.month.toString().padLeft(2, '0')}.${memory.memoryDate!.day.toString().padLeft(2, '0')}'
        : '';

    return GestureDetector(
      onTap: () async {
        final result = await showMemoryDetailSheet(context, widget.mapId, memory.memoryId);
        if (result == true) _loadMemories();
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // 썸네일
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: memory.thumbnailUrl != null
                  ? Image.network(
                      memory.thumbnailUrl!,
                      width: 64,
                      height: 64,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _buildPlaceholder(memory.category),
                    )
                  : _buildPlaceholder(memory.category),
            ),
            const SizedBox(width: 14),
            // 정보
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    memory.title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF191919),
                      letterSpacing: -0.3,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.place, size: 14, color: Color(0xFFFF7A7A)),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(
                          memory.placeName,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF888888),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (dateStr.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      dateStr,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFFBBBBBB),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, size: 14, color: Color(0xFFBBBBBB)),
          ],
        ),
      ),
    );
  }

  static const _categoryIcons = {
    '음식점': Icons.restaurant,
    '카페': Icons.coffee,
    '영화관': Icons.movie,
    '쇼핑': Icons.shopping_bag,
    '관광지': Icons.temple_buddhist,
  };

  static const _categoryColors = {
    '음식점': Color(0xFFFF9800),
    '카페': Color(0xFF8D6E63),
    '영화관': Color(0xFF7E57C2),
    '쇼핑': Color(0xFF42A5F5),
    '관광지': Color(0xFF66BB6A),
  };

  Widget _buildPlaceholder(String? category) {
    final icon = _categoryIcons[category];
    final color = _categoryColors[category];
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: const Color(0xFFF5F3F0),
        borderRadius: BorderRadius.circular(12),
      ),
      child: icon != null
          ? Icon(icon, color: color, size: 28)
          : const Icon(Icons.place, color: Color(0xFFFF7A7A), size: 28),
    );
  }
}
