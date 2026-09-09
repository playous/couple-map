import 'package:dio/dio.dart';
import '../../../../core/network/dio_client.dart';

class CalendarMemory {
  final int mapId;
  final int memoryId;
  final String title;
  final String placeName;
  final DateTime? memoryDate;
  final String? category;
  final String? thumbnailUrl;

  const CalendarMemory({
    required this.mapId,
    required this.memoryId,
    required this.title,
    required this.placeName,
    this.memoryDate,
    this.category,
    this.thumbnailUrl,
  });

  factory CalendarMemory.fromJson(Map<String, dynamic> json) {
    return CalendarMemory(
      mapId: json['mapId'] as int,
      memoryId: json['memoryId'] as int,
      title: json['title'] as String,
      placeName: json['placeName'] as String,
      memoryDate: json['memoryDate'] != null
          ? DateTime.parse(json['memoryDate'] as String)
          : null,
      category: json['category'] as String?,
      thumbnailUrl: json['thumbnailUrl'] as String?,
    );
  }
}

class CalendarRepository {
  // 월별 캐시: "2024-3" → List<CalendarMemory>
  final Map<String, List<CalendarMemory>> _cache = {};

  static String cacheKey(int year, int month) => '$year-$month';

  Future<List<CalendarMemory>> getCalendarMemories(
    int year,
    int month, {
    bool forceRefresh = false,
  }) async {
    final key = cacheKey(year, month);
    if (!forceRefresh && _cache.containsKey(key)) {
      return _cache[key]!;
    }

    try {
      final response = await DioClient.instance.get(
        '/api/calendar/memories',
        queryParameters: {'year': year, 'month': month},
      );
      final list = (response.data['data'] as List? ?? [])
          .map((e) => CalendarMemory.fromJson(e as Map<String, dynamic>))
          .toList();
      _cache[key] = list;
      return list;
    } on DioException catch (e) {
      throw DioClient.handleError(e);
    }
  }

  // 추억 수정은 날짜를 다른 달로 옮길 수 있어 어느 달이 바뀌었는지 특정하기 어렵다.
  // 캐시가 월당 30건 안팎이라 통째로 비우고 다시 받는 비용이 작다
  void invalidateCache({int? year, int? month}) {
    if (year != null && month != null) {
      _cache.remove(cacheKey(year, month));
    } else {
      _cache.clear();
    }
  }
}
