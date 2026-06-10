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
  // 연도별 캐시: year → List<CalendarMemory>
  final Map<int, List<CalendarMemory>> _cache = {};

  Future<List<CalendarMemory>> getCalendarMemories(
    int year, {
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _cache.containsKey(year)) {
      return _cache[year]!;
    }

    try {
      final response = await DioClient.instance.get(
        '/api/calendar/memories',
        queryParameters: {'year': year},
      );
      final list = (response.data['data'] as List? ?? [])
          .map((e) => CalendarMemory.fromJson(e as Map<String, dynamic>))
          .toList();
      _cache[year] = list;
      return list;
    } on DioException catch (e) {
      throw DioClient.handleError(e);
    }
  }

  void invalidateCache([int? year]) {
    if (year != null) {
      _cache.remove(year);
    } else {
      _cache.clear();
    }
  }
}
