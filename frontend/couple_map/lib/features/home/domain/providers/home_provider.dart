import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/map_card_model.dart';
import '../../data/repositories/home_repository.dart';

final homeRepositoryProvider = Provider<HomeRepository>((_) => HomeRepository());

// 지도 목록 상태
final mapListProvider = FutureProvider<List<MapCardModel>>(
  (ref) => ref.read(homeRepositoryProvider).getMapList(),
);
