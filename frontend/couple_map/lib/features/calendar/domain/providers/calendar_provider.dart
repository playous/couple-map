import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/repositories/calendar_repository.dart';

final calendarRepositoryProvider = Provider<CalendarRepository>((_) => CalendarRepository());

// 추억이 생성, 수정, 삭제되면 증가한다. 캘린더는 홈의 IndexedStack에 남아 있어 탭을 옮겨도
// initState가 다시 돌지 않으므로, 이 값을 구독해 화면에 들고 있는 데이터까지 버리게 한다
final calendarVersionProvider = StateProvider<int>((_) => 0);

// 추억을 바꾼 화면에서 호출한다. 리포지토리 캐시를 비우고 캘린더에 다시 받으라고 알린다
void invalidateCalendar(WidgetRef ref) {
  ref.read(calendarRepositoryProvider).invalidateCache();
  ref.read(calendarVersionProvider.notifier).state++;
}
