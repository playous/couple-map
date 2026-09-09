import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:kakao_map_plugin/kakao_map_plugin.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../config/app_config.dart';
import 'dart:async';
import '../../../auth/domain/providers/auth_provider.dart';
import '../../data/models/place_model.dart';
import '../../../memory/data/models/memory_model.dart';
import '../../../memory/domain/providers/memory_provider.dart';
import '../../../memory/presentation/screens/memory_detail_screen.dart';

class _ClustererMarker extends Marker {
  _ClustererMarker({
    required super.markerId,
    required super.latLng,
    super.width = 24,
    super.height = 30,
    super.icon,
  });

  @override
  Map<String, dynamic> toJson() {
    final json = super.toJson();
    final iconObj = icon;
    json['icon'] = null;
    final base64 = iconObj?.imageSrc ?? '';
    json['imageSrc'] = base64.isNotEmpty ? 'data:image/png;base64,$base64' : '';
    json['imageType'] = null;
    return json;
  }
}

class MapDetailScreen extends ConsumerStatefulWidget {
  final int mapId;
  final String? mapName;
  final String? description;
  final int memberCount;
  final String? category;

  const MapDetailScreen({
    super.key,
    required this.mapId,
    this.mapName,
    this.description,
    this.memberCount = 1,
    this.category,
  });

  @override
  ConsumerState<MapDetailScreen> createState() => _MapDetailScreenState();
}

class _MapDetailScreenState extends ConsumerState<MapDetailScreen> {
  KakaoMapController? mapController;
  final TextEditingController _searchController = TextEditingController();
  final Dio _dio = Dio();
  List<PlaceModel> _searchResults = [];
  List<MemoryMarker> _memories = [];
  bool _isSearching = false;
  bool _showResults = false;

  // 필터 상태
  bool _showFilter = false;
  String? _filterCategory;
  DateTime _filterStartDate = DateTime(DateTime.now().year, 1, 1);
  DateTime _filterEndDate = DateTime.now();

  Timer? _debounce;
  Clusterer? _cachedClusterer;

  final LatLng _initialPosition = LatLng(37.5665, 126.9780);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadMemories();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    if (_debounce?.isActive ?? false) {
      _debounce!.cancel();
    }
    super.dispose();
  }

  void _handleSearch(String query) {
    if (_debounce?.isActive ?? false) {
      _debounce!.cancel();
    }

    _debounce = Timer(const Duration(milliseconds: 500), () {
      _searchPlaces(query);
    });
  }

  Future<void> _searchPlaces(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _showResults = false;
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _showResults = true;
    });

    try {
      final restApiKey = AppConfig.kakaoRestApiKey;
      final response = await _dio.get(
        'https://dapi.kakao.com/v2/local/search/keyword.json',
        queryParameters: {'query': query},
        options: Options(headers: {'Authorization': 'KakaoAK $restApiKey'}),
      );

      if (response.statusCode == 200) {
        final documents = response.data['documents'] as List;
        setState(() {
          _searchResults = documents.map((doc) => PlaceModel.fromJson(doc)).toList();
          _isSearching = false;
        });
      }
    } catch (e) {
      setState(() {
        _isSearching = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('검색 실패: $e'),
            backgroundColor: Colors.red[400],
          ),
        );
      }
    }
  }

  Future<void> _moveToPlace(PlaceModel place) async {
    final lat = double.parse(place.y);
    final lng = double.parse(place.x);

    mapController?.setCenter(LatLng(lat, lng));
    mapController?.setLevel(3);

    setState(() {
      _showResults = false;
      _searchController.clear();
    });

    final result = await context.push<bool>(
      '/map/${widget.mapId}/memory/create',
      extra: {
        'placeName': place.placeName,
        'addressName': place.addressName,
        'latitude': lat,
        'longitude': lng,
      },
    );

    if (result == true && mounted) {
      await _loadMemories();
    }
  }

  Future<void> _loadMemories() async {
    if (!mounted) return;

    try {
      final auth = ref.read(authProvider);
      if (auth is! AuthSuccess) return;

      final memories = await ref.read(memoryRepositoryProvider).getMemoryMarkers(widget.mapId);

      if (!mounted) return;

      _memories = memories;
      await _updateClusterer();
      if (!mounted) return;
      setState(() {});

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('추억 목록을 불러오지 못했어요')),
        );
      }
    }
  }

  List<MemoryMarker> get _filteredMemories {
    return _memories.where((m) {
      if (_filterCategory != null && m.category != _filterCategory) return false;
      if (m.memoryDate != null) {
        if (m.memoryDate!.isBefore(_filterStartDate)) return false;
        if (m.memoryDate!.isAfter(_filterEndDate.add(const Duration(days: 1)))) return false;
      }
      return true;
    }).toList();
  }

  static const List<Map<String, dynamic>> _filterCategories = [
    {'label': '전체', 'value': null, 'icon': null, 'color': null},
    {'label': '음식점', 'value': '음식점', 'icon': Icons.restaurant, 'color': Color(0xFFFF9800)},
    {'label': '카페', 'value': '카페', 'icon': Icons.coffee, 'color': Color(0xFF8D6E63)},
    {'label': '영화관', 'value': '영화관', 'icon': Icons.movie, 'color': Color(0xFF7E57C2)},
    {'label': '쇼핑', 'value': '쇼핑', 'icon': Icons.shopping_bag, 'color': Color(0xFF42A5F5)},
    {'label': '관광지', 'value': '관광지', 'icon': Icons.temple_buddhist, 'color': Color(0xFF66BB6A)},
  ];

  static const _categoryMarkerAssets = {
    '음식점': 'assets/markers/marker_food.png',
    '카페': 'assets/markers/marker_cafe.png',
    '영화관': 'assets/markers/marker_movie.png',
    '쇼핑': 'assets/markers/marker_shopping.png',
    '관광지': 'assets/markers/marker_tourism.png',
  };
  static const _defaultMarkerAsset = 'assets/markers/marker_default.png';

  final Map<String, MarkerIcon> _markerIconCache = {};

  Future<MarkerIcon> _getMarkerIcon(String? category) async {
    final asset = _categoryMarkerAssets[category] ?? _defaultMarkerAsset;
    if (_markerIconCache.containsKey(asset)) return _markerIconCache[asset]!;
    final icon = await MarkerIcon.fromAsset(asset);
    _markerIconCache[asset] = icon;
    return icon;
  }

  Future<void> _updateClusterer() async {
    mapController?.clearMarker();

    final filtered = _filteredMemories;
    if (filtered.isEmpty) {
      _cachedClusterer = null;
      return;
    }

    final markers = <Marker>[];
    for (final memory in filtered) {
      final icon = await _getMarkerIcon(memory.category);
      markers.add(_ClustererMarker(
        markerId: memory.memoryId.toString(),
        latLng: LatLng(memory.latitude, memory.longitude),
        width: 30,
        height: 30,
        icon: icon,
      ));
    }


    _cachedClusterer = Clusterer(
      markers: markers,
      minLevel: 1,
      disableClickZoom: false,
      styles: [
        ClustererStyle(
          width: 40,
          height: 40,
          background: const Color(0xFF3182F6),
          color: Colors.white,
          borderRadius: 20,
          textAlign: 'center',
          lineHeight: 40,
        ),
      ],
    );
  }

  Future<void> _onMarkerTap(String markerId, LatLng latLng, int zoomLevel) async {

    mapController?.setCenter(latLng);
    mapController?.setLevel(3);

    final memoryId = int.tryParse(markerId);
    if (memoryId != null) {
      final result = await showMemoryDetailSheet(context, widget.mapId, memoryId);
      if (result == true && mounted) _loadMemories();
    }
  }

  void _onClustererTap(LatLng latLng, int zoomLevel, List<Marker> clusterMarkers) {

    mapController?.setCenter(latLng);
    mapController?.setLevel((zoomLevel - 2).clamp(1, 14));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Color(0xFF191919), size: 20),
          onPressed: () => context.pop(),
        ),
        title: Text(
          widget.mapName ?? '',
          style: const TextStyle(
            color: Color(0xFF191919),
            fontSize: 18,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
        ),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: () => context.push(
              '/map/${widget.mapId}/settings',
              extra: {
                'mapName': widget.mapName ?? '',
                'description': widget.description,
                'memberCount': widget.memberCount,
                'category': widget.category,
              },
            ),
            child: const Text(
              '설정',
              style: TextStyle(
                color: Color(0xFFFF7A7A),
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Stack(
        children: [
          Positioned.fill(
            child: KakaoMap(
              onMapCreated: (controller) {
                mapController = controller;
                controller.setLevel(5);
              },
              center: _initialPosition,
              clusterer: _cachedClusterer,
              onMarkerTap: _onMarkerTap,
              onMarkerClustererTap: _onClustererTap,
            ),
          ),

          Positioned(
            top: 12,
            left: 16,
            right: 16,
            child: Row(
              children: [
                Expanded(
                  child: Material(
                    elevation: 2,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFECE8E4)),
                      ),
                      child: TextField(
                        controller: _searchController,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                        decoration: InputDecoration(
                          hintText: '장소, 주소 검색',
                          hintStyle: const TextStyle(
                            color: Color(0xFFBBBBBB),
                            fontWeight: FontWeight.w400,
                            fontSize: 15,
                          ),
                          prefixIcon: const Icon(Icons.search, color: Color(0xFFBBBBBB), size: 22),
                          suffixIcon: _searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, color: Color(0xFFBBBBBB), size: 18),
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() {
                                      _searchResults = [];
                                      _showResults = false;
                                    });
                                    if (_debounce?.isActive ?? false) {
                                      _debounce!.cancel();
                                    }
                                  },
                                )
                              : null,
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onChanged: (value) {
                          setState(() {});
                          _handleSearch(value);
                        },
                        onSubmitted: _searchPlaces,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Material(
                  elevation: 2,
                  borderRadius: BorderRadius.circular(12),
                  child: GestureDetector(
                    onTap: () => setState(() => _showFilter = !_showFilter),
                    child: Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: _showFilter ? const Color(0xFFFF7A7A) : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _showFilter ? const Color(0xFFFF7A7A) : const Color(0xFFECE8E4),
                        ),
                      ),
                      child: Icon(
                        Icons.tune,
                        color: _showFilter ? Colors.white : const Color(0xFF555555),
                        size: 22,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Material(
                  elevation: 2,
                  borderRadius: BorderRadius.circular(12),
                  child: GestureDetector(
                    onTap: () => context.push('/map/${widget.mapId}/memories'),
                    child: Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFECE8E4)),
                      ),
                      child: const Icon(
                        Icons.list_alt,
                        color: Color(0xFF555555),
                        size: 22,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          if (_showFilter)
            Positioned(
              top: 70,
              left: 16,
              right: 16,
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '카테고리',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _filterCategories.map((cat) {
                          final isSelected = _filterCategory == cat['value'];
                          return GestureDetector(
                            onTap: () => setState(() {
                              _filterCategory = cat['value'] as String?;
                            }),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: isSelected ? const Color(0xFFFFF0F0) : const Color(0xFFF5F3F0),
                                borderRadius: BorderRadius.circular(20),
                                border: isSelected
                                    ? Border.all(color: const Color(0xFFFF7A7A))
                                    : null,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (cat['icon'] != null) ...[
                                    Icon(
                                      cat['icon'] as IconData,
                                      size: 16,
                                      color: cat['color'] as Color,
                                    ),
                                    const SizedBox(width: 6),
                                  ],
                                  Text(
                                    cat['label'] as String,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                      color: isSelected ? const Color(0xFFFF7A7A) : const Color(0xFF888888),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '기간',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () async {
                                final date = await showDatePicker(
                                  context: context,
                                  initialDate: _filterStartDate,
                                  firstDate: DateTime(2000),
                                  lastDate: _filterEndDate,
                                  builder: (context, child) => Theme(
                                    data: Theme.of(context).copyWith(
                                      colorScheme: const ColorScheme.light(primary: Color(0xFFFF7A7A)),
                                    ),
                                    child: child!,
                                  ),
                                );
                                if (date != null && mounted) {
                                  setState(() => _filterStartDate = date);
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF5F3F0),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '${_filterStartDate.year}.${_filterStartDate.month.toString().padLeft(2, '0')}.${_filterStartDate.day.toString().padLeft(2, '0')}',
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8),
                            child: Text('—', style: TextStyle(color: Color(0xFF888888))),
                          ),
                          Expanded(
                            child: GestureDetector(
                              onTap: () async {
                                final date = await showDatePicker(
                                  context: context,
                                  initialDate: _filterEndDate,
                                  firstDate: _filterStartDate,
                                  lastDate: DateTime.now(),
                                  builder: (context, child) => Theme(
                                    data: Theme.of(context).copyWith(
                                      colorScheme: const ColorScheme.light(primary: Color(0xFFFF7A7A)),
                                    ),
                                    child: child!,
                                  ),
                                );
                                if (date != null && mounted) {
                                  setState(() => _filterEndDate = date);
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF5F3F0),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '${_filterEndDate.year}.${_filterEndDate.month.toString().padLeft(2, '0')}.${_filterEndDate.day.toString().padLeft(2, '0')}',
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            flex: 1,
                            child: OutlinedButton(
                              onPressed: () async {
                                _filterCategory = null;
                                _filterStartDate = DateTime(DateTime.now().year, 1, 1);
                                _filterEndDate = DateTime.now();
                                await _updateClusterer();
                                if (mounted) setState(() {});
                              },
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Color(0xFFDDDDDD)),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                              child: const Text(
                                '초기화',
                                style: TextStyle(
                                  color: Color(0xFF555555),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 2,
                            child: ElevatedButton(
                              onPressed: () async {
                                _showFilter = false;
                                await _updateClusterer();
                                if (mounted) setState(() {});
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFFF7A7A),
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                              child: const Text(
                                '적용',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),

          if (_showResults)
            Positioned(
              top: 80,
              left: 16,
              right: 16,
              bottom: 16,
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: _isSearching
                      ? const Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Color(0xFF3182F6),
                            ),
                          ),
                        )
                      : _searchResults.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.search_off,
                                size: 64,
                                color: Colors.grey[300],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                '검색 결과가 없습니다',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(8),
                          itemCount: _searchResults.length,
                          separatorBuilder: (context, index) =>
                              Divider(height: 1, color: Colors.grey[200]),
                          itemBuilder: (context, index) {
                            final place = _searchResults[index];
                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              leading: Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFF3182F6,
                                  ).withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.place,
                                  color: Color(0xFF3182F6),
                                  size: 28,
                                ),
                              ),
                              title: Text(
                                place.placeName,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF191919),
                                  letterSpacing: -0.3,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (place.categoryName.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        place.categoryName,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                          color: Colors.grey[500],
                                        ),
                                      ),
                                    ),
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      place.addressName,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.grey[700],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              trailing: const Icon(
                                Icons.arrow_forward_ios,
                                size: 16,
                                color: Color(0xFF3182F6),
                              ),
                              onTap: () => _moveToPlace(place),
                            );
                          },
                        ),
                ),
              ),
            ),
        ],
      ),
      ),
    );
  }
}
