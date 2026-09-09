import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../auth/domain/providers/auth_provider.dart';
import '../../../memory/presentation/screens/memory_detail_screen.dart';
import '../../data/repositories/calendar_repository.dart';
import '../../domain/providers/calendar_provider.dart';

// ─── 캘린더 스크린 ──────────────────────────────────────────────────────────
class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  DateTime _currentMonth = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime _selectedDate = DateTime.now();

  // 날짜 키 → 추억 리스트. 넘겨본 달이 쌓인다
  final Map<String, List<CalendarMemory>> _memoryMap = {};
  // 응답을 받은 달. "아직 안 받음"과 "추억이 없음"을 구분하는 데 쓴다
  final Set<String> _loadedMonths = {};
  bool _isLoading = true;

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

  static const _categoryBgColors = {
    '음식점': Color(0xFFFFF3E0),
    '카페': Color(0xFFEFEBE9),
    '영화관': Color(0xFFEDE7F6),
    '쇼핑': Color(0xFFE3F2FD),
    '관광지': Color(0xFFE8F5E9),
  };

  @override
  void initState() {
    super.initState();
    _loadMemories();
  }

  Future<String?> _getToken() async {
    final auth = ref.read(authProvider);
    if (auth is AuthSuccess) return auth.token.accessToken;
    return await ref.read(authRepositoryProvider).getAccessToken();
  }

  Future<void> _loadMemories({bool forceRefresh = false}) async {
    final year = _currentMonth.year;
    final month = _currentMonth.month;
    setState(() => _isLoading = true);
    try {
      final token = await _getToken();
      if (token == null) return;

      final calendarRepo = ref.read(calendarRepositoryProvider);
      final memories = await calendarRepo.getCalendarMemories(
        year,
        month,
        forceRefresh: forceRefresh,
      );

      final newMap = <String, List<CalendarMemory>>{};
      for (final memory in memories) {
        if (memory.memoryDate == null) continue;
        final key = _dateKey(memory.memoryDate!);
        newMap.putIfAbsent(key, () => []).add(memory);
      }

      if (mounted) {
        setState(() {
          // 이번에 받은 달의 날짜만 갈아끼우고 다른 달은 남긴다. 이미 본 달로 돌아갈 때
          // 다시 기다리지 않고, 빠르게 넘겨 응답 순서가 뒤바뀌어도 서로를 덮지 않는다
          final prefix = _monthPrefix(year, month);
          _memoryMap.removeWhere((key, _) => key.startsWith(prefix));
          _memoryMap.addAll(newMap);
          _loadedMonths.add(CalendarRepository.cacheKey(year, month));
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _monthPrefix(int year, int month) =>
      '$year-${month.toString().padLeft(2, '0')}';

  bool get _isCurrentMonthLoaded => _loadedMonths
      .contains(CalendarRepository.cacheKey(_currentMonth.year, _currentMonth.month));

  String _dateKey(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  List<CalendarMemory> get _selectedEntries =>
      _memoryMap[_dateKey(_selectedDate)] ?? [];

  int get _monthMemoryCount {
    int count = 0;
    _memoryMap.forEach((key, value) {
      final parts = key.split('-');
      if (parts.length >= 2 &&
          parts[0] == _currentMonth.year.toString() &&
          parts[1] == _currentMonth.month.toString().padLeft(2, '0')) {
        count += value.length;
      }
    });
    return count;
  }

  bool _hasMemory(DateTime date) =>
      (_memoryMap[_dateKey(date)] ?? []).isNotEmpty;

  void _changeMonth(int delta) {
    final newMonth = DateTime(
      _currentMonth.year,
      _currentMonth.month + delta,
    );
    setState(() {
      _currentMonth = newMonth;
      _selectedDate = DateTime(newMonth.year, newMonth.month, 1);
    });
    // 달마다 따로 받으므로 연도가 그대로여도 다시 받는다.
    // 이미 받은 달이면 리포지토리 캐시에서 바로 돌아온다
    _loadMemories();
  }

  @override
  Widget build(BuildContext context) {
    // 추억이 바뀌면 들고 있던 데이터를 버리고 지금 보고 있는 달을 다시 받는다
    ref.listen<int>(calendarVersionProvider, (_, __) {
      _memoryMap.clear();
      _loadedMonths.clear();
      _loadMemories(forceRefresh: true);
    });

    return Scaffold(
      backgroundColor: const Color(0xFFFDFBF7),
      body: SafeArea(
        // 첫 진입에만 스피너를 띄운다. 월을 넘길 때마다 화면 전체가 사라졌다 돌아오면
        // 응답이 빨라도 깜빡임이 보인다. 그리드는 날짜 계산만으로 그릴 수 있으므로
        // 먼저 그려두고 점만 나중에 채운다
        child: _isLoading && _memoryMap.isEmpty
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFFFF8E8E)),
              )
            : Column(
                children: [
                  _buildAppBar(),
                  Expanded(
                    child: RefreshIndicator(
                      color: const Color(0xFFFF8E8E),
                      onRefresh: () => _loadMemories(forceRefresh: true),
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 16),
                              _buildMonthHeader(),
                              const SizedBox(height: 16),
                              _buildCalendarCard(),
                              const SizedBox(height: 24),
                              _buildMemorySection(),
                              const SizedBox(height: 32),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
            ),
      ),
    );
  }

  // ── 앱바 ──
  Widget _buildAppBar() {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: const Align(
        alignment: Alignment(0, 1.0),
        child: Text(
          '캘린더',
          style: TextStyle(
            fontFamily: 'NotoSerifKR',
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: Color(0xFF2C2C2C),
            letterSpacing: -0.3,
          ),
        ),
      ),
    );
  }

  // ── 월 헤더 ──
  Widget _buildMonthHeader() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            GestureDetector(
              onTap: () => _changeMonth(-1),
              child: Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                child: const Text(
                  '❮',
                  style: TextStyle(fontSize: 14, color: Color(0xFF888888)),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Text(
              '${_currentMonth.year}년 ${_currentMonth.month}월',
              style: const TextStyle(
                fontFamily: 'NotoSerifKR',
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFF2C2C2C),
              ),
            ),
            const SizedBox(width: 16),
            GestureDetector(
              onTap: () => _changeMonth(1),
              child: Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                child: const Text(
                  '❯',
                  style: TextStyle(fontSize: 14, color: Color(0xFF888888)),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '${_isCurrentMonth ? '이번 달' : '${_currentMonth.month}월'} 추억 $_monthMemoryCount개',
          style: const TextStyle(
            fontFamily: 'NotoSansKR',
            fontSize: 13,
            fontWeight: FontWeight.w400,
            color: Color(0xFF999999),
          ),
        ),
      ],
    );
  }

  // ── 캘린더 카드 ──
  Widget _buildCalendarCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildDayHeaders(),
          const SizedBox(height: 8),
          _buildCalendarGrid(),
        ],
      ),
    );
  }

  Widget _buildDayHeaders() {
    const days = ['일', '월', '화', '수', '목', '금', '토'];
    return Row(
      children: days.map((day) {
        final isRed = day == '일';
        return Expanded(
          child: Center(
            child: Text(
              day,
              style: TextStyle(
                fontFamily: 'NotoSansKR',
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: isRed
                    ? const Color(0xFFFF8E8E)
                    : const Color(0xFF999999),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildCalendarGrid() {
    final firstDay =
        DateTime(_currentMonth.year, _currentMonth.month, 1);
    final lastDay =
        DateTime(_currentMonth.year, _currentMonth.month + 1, 0);
    final startWeekday = firstDay.weekday % 7; // 0=Sun
    final totalDays = lastDay.day;

    final cells = <Widget>[];
    for (int i = 0; i < startWeekday; i++) {
      cells.add(const SizedBox());
    }
    for (int day = 1; day <= totalDays; day++) {
      cells.add(
        _buildDayCell(DateTime(_currentMonth.year, _currentMonth.month, day)),
      );
    }

    final rows = <Widget>[];
    for (int i = 0; i < cells.length; i += 7) {
      final rowCells =
          cells.sublist(i, (i + 7).clamp(0, cells.length)).toList();
      while (rowCells.length < 7) { rowCells.add(const SizedBox()); }
      rows.add(Row(
          children: rowCells.map((c) => Expanded(child: c)).toList()));
      if (i + 7 < cells.length) rows.add(const SizedBox(height: 4));
    }

    return Column(children: rows);
  }

  Widget _buildDayCell(DateTime date) {
    final isSelected = _selectedDate.day == date.day &&
        _selectedDate.month == date.month &&
        _selectedDate.year == date.year;
    final hasMemory = _hasMemory(date);
    final isToday = DateTime.now().day == date.day &&
        DateTime.now().month == date.month &&
        DateTime.now().year == date.year;
    final isSunday = date.weekday == DateTime.sunday;

    return GestureDetector(
      onTap: () => setState(() => _selectedDate = date),
      child: AspectRatio(
        aspectRatio: 1,
        child: Container(
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFFFF8E8E)
                : (isToday ? const Color(0xFFFFE4E4) : Colors.transparent),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Text(
                '${date.day}',
                style: TextStyle(
                  fontFamily: 'NotoSansKR',
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: isSelected
                      ? Colors.white
                      : (isSunday
                          ? const Color(0xFFFF8E8E)
                          : const Color(0xFF2C2C2C)),
                ),
              ),
              if (hasMemory && !isSelected)
                Positioned(
                  bottom: 4,
                  child: Container(
                    width: 16,
                    height: 2,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF8E8E),
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 추억 섹션 ──
  bool get _isCurrentMonth {
    final now = DateTime.now();
    return _currentMonth.year == now.year && _currentMonth.month == now.month;
  }

  bool get _isSelectedToday {
    final now = DateTime.now();
    return _selectedDate.year == now.year &&
        _selectedDate.month == now.month &&
        _selectedDate.day == now.day;
  }

  Widget _buildMemorySection() {
    final entries = _selectedEntries;
    final month = _selectedDate.month;
    final day = _selectedDate.day;

    final count = entries.length;
    final title = _isSelectedToday
        ? (count > 0 ? '오늘의 추억 ($count개)' : '오늘의 추억 ($month월 $day일)')
        : (count > 0 ? '$month월 $day일의 추억 ($count개)' : '$month월 $day일의 추억');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontFamily: 'NotoSansKR',
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Color(0xFF2C2C2C),
          ),
        ),
        const SizedBox(height: 16),
        // 아직 응답이 안 온 달에 "추억이 없어요"를 띄우면, 곧 타일로 바뀌면서 높이가 출렁인다.
        // 받기 전에는 비워두고 한 번에 그린다
        if (!_isCurrentMonthLoaded)
          const SizedBox.shrink()
        else if (entries.isEmpty)
          _buildEmptyMemory()
        else
          ...entries.map((e) => _buildMemoryTile(e)),
      ],
    );
  }

  Widget _buildEmptyMemory() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
          children: [
            const Text('📝', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 16),
            Text(
              _isSelectedToday ? '오늘 추억이 없어요' : '이날 추억이 없어요',
              style: const TextStyle(
                fontFamily: 'NotoSansKR',
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Color(0xFF2C2C2C),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              '새로운 추억을 기록해보세요!',
              style: TextStyle(
                fontFamily: 'NotoSansKR',
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: Color(0xFF999999),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMemoryTile(CalendarMemory memory) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => showMemoryDetailSheet(context, memory.mapId, memory.memoryId),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: memory.thumbnailUrl != null
                        ? Colors.transparent
                        : (_categoryBgColors[memory.category] ?? const Color(0xFFFFF0F0)),
                    shape: BoxShape.circle,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: memory.thumbnailUrl != null
                      ? Image.network(
                          memory.thumbnailUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Center(
                            child: Icon(
                              _categoryIcons[memory.category] ?? Icons.place,
                              color: _categoryColors[memory.category] ?? const Color(0xFFFF7A7A),
                              size: 20,
                            ),
                          ),
                        )
                      : Center(
                          child: Icon(
                            _categoryIcons[memory.category] ?? Icons.place,
                            color: _categoryColors[memory.category] ?? const Color(0xFFFF7A7A),
                            size: 20,
                          ),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        memory.title,
                        style: const TextStyle(
                          fontFamily: 'NotoSansKR',
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF2C2C2C),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        memory.placeName,
                        style: const TextStyle(
                          fontFamily: 'NotoSansKR',
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          color: Color(0xFF999999),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  color: Color(0xFFCCCCCC),
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
