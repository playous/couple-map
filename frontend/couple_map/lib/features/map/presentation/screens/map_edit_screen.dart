import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../auth/domain/providers/auth_provider.dart';
import '../../data/models/map_model.dart';
import '../../domain/providers/map_provider.dart';

class MapEditScreen extends ConsumerStatefulWidget {
  final int mapId;

  const MapEditScreen({
    super.key,
    required this.mapId,
  });

  @override
  ConsumerState<MapEditScreen> createState() => _MapEditScreenState();
}

class _MapEditScreenState extends ConsumerState<MapEditScreen> {
  static const int _mapNameMaxLength = 20;
  static const int _descriptionMaxLength = 20;
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descController = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  File? _newCoverImage;
  String? _selectedDefaultCover;
  String _selectedCategory = 'Solo';
  bool _isLoading = true;
  bool _isSaving = false;

  // 원본 데이터 (변경 감지용)
  String _initialName = '';
  String _initialDesc = '';
  String _initialCategory = 'Solo';
  String? _backgroundImageUrl;

  static const Map<String, String> _categories = {
    'Solo': '나 혼자',
    'Friends': '친구들과',
    'Couple': '연인과',
    'Family': '가족',
  };

  String _categoryLabel(String key) => _categories[key] ?? _categories['Solo']!;

  String _categoryKeyFromServer(String? category) {
    if (category == null || category.isEmpty) return 'Solo';
    if (_categories.containsKey(category)) return category;
    for (final entry in _categories.entries) {
      if (entry.value == category) return entry.key;
    }
    return 'Solo';
  }

  static const List<String> _defaultCovers = [
    'assets/images/covers/cover_1.jpg',
    'assets/images/covers/cover_2.jpg',
    'assets/images/covers/cover_3.jpg',
    'assets/images/covers/cover_4.jpg',
    'assets/images/covers/cover_5.jpg',
    'assets/images/covers/cover_6.jpg',
  ];

  @override
  void initState() {
    super.initState();
    _nameController.addListener(() => setState(() {}));
    _loadMapDetail();
  }

  Future<void> _loadMapDetail() async {
    final auth = ref.read(authProvider);
    if (auth is! AuthSuccess) return;
    try {
      final map = await ref.read(mapRepositoryProvider).getMapDetail(
        widget.mapId,
      );
      if (mounted) {
        setState(() {
          _nameController.text = map.mapName;
          _descController.text = map.description ?? '';
          _selectedCategory = _categoryKeyFromServer(map.category);
          _backgroundImageUrl = map.backgroundUrl;
          _initialName = map.mapName;
          _initialDesc = map.description ?? '';
          _initialCategory = _selectedCategory;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('로딩 실패: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _pickCoverImage() async {
    var status = await Permission.photos.status;
    if (!status.isGranted && !status.isLimited) {
      status = await Permission.photos.request();
    }
    if (!status.isGranted && !status.isLimited) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('사진 접근 권한이 필요합니다')),
        );
      }
      return;
    }
    final picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked != null && mounted) {
      setState(() {
        _newCoverImage = File(picked.path);
        _selectedDefaultCover = null;
      });
    }
  }

  bool get _hasChanges {
    return _nameController.text.trim() != _initialName ||
        _descController.text.trim() != _initialDesc ||
        _newCoverImage != null ||
        _selectedDefaultCover != null ||
        _selectedCategory != _initialCategory;
  }

  Future<File?> _assetToTempFile(String assetPath) async {
    final data = await rootBundle.load(assetPath);
    final fileName = assetPath.split('/').last;
    final tempDir = Directory.systemTemp;
    final file = File('${tempDir.path}/$fileName');
    await file.writeAsBytes(data.buffer.asUint8List());
    return file;
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final description = _descController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('지도 이름을 입력해주세요')),
      );
      return;
    }
    if (name.length > _mapNameMaxLength) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('지도 이름은 20자 이하로 입력해주세요')),
      );
      return;
    }
    if (description.length > _descriptionMaxLength) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('설명은 20자 이하로 입력해주세요')),
      );
      return;
    }
    final auth = ref.read(authProvider);
    if (auth is! AuthSuccess) return;

    setState(() => _isSaving = true);
    try {
      File? coverFile = _newCoverImage;
      if (coverFile == null && _selectedDefaultCover != null) {
        coverFile = await _assetToTempFile(_selectedDefaultCover!);
      }

      await ref.read(mapRepositoryProvider).updateMap(
        widget.mapId,
        name,
        description.isNotEmpty ? description : null,
        _categoryLabel(_selectedCategory),
        coverFile,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('수정되었어요!')),
        );
        context.pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('오류: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
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
          '지도 수정',
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
          : Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildCoverSection(),

                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildLabel('지도 이름'),
                        const SizedBox(height: 8),
                        _buildTextField(
                          controller: _nameController,
                          hintText: '지도 이름을 입력해주세요',
                          maxLength: _mapNameMaxLength,
                        ),
                        const SizedBox(height: 20),

                        _buildLabel('설명'),
                        const SizedBox(height: 8),
                        _buildTextField(
                          controller: _descController,
                          hintText: '짧은 설명 (선택)',
                          maxLines: 3,
                          maxLength: _descriptionMaxLength,
                        ),
                        const SizedBox(height: 20),

                        _buildLabel('카테고리'),
                        const SizedBox(height: 10),
                        Row(
                          children: _categories.entries.map((entry) {
                            final key = entry.key;
                            final label = entry.value;
                            final isSelected = _selectedCategory == key;
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: GestureDetector(
                                onTap: () => setState(() => _selectedCategory = key),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? const Color(0xFFFFF0F0)
                                        : const Color(0xFFF1F3F5),
                                    borderRadius: BorderRadius.circular(20),
                                    border: isSelected
                                        ? Border.all(color: const Color(0xFFFFB5B5))
                                        : null,
                                  ),
                                  child: Text(
                                    label,
                                    style: TextStyle(
                                      color: isSelected
                                          ? const Color(0xFFFFB5B5)
                                          : const Color(0xFF868E96),
                                      fontSize: 14,
                                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          Padding(
            padding: EdgeInsets.fromLTRB(
              20, 12, 20,
              MediaQuery.of(context).padding.bottom + 20,
            ),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _isSaving || _nameController.text.trim().isEmpty || !_hasChanges
                    ? null
                    : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF7A7A),
                  disabledBackgroundColor: const Color(0xFFFFB5B5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
                child: _isSaving
                    ? const SizedBox(
                        width: 22, height: 22,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                      )
                    : const Text(
                        '저장',
                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCoverSection() {
    final hasNewImage = _newCoverImage != null;
    final hasDefaultCover = _selectedDefaultCover != null;
    final hasExistingImage = _backgroundImageUrl != null && !hasNewImage && !hasDefaultCover;
    final hasAnyCover = hasNewImage || hasDefaultCover || hasExistingImage;

    return SizedBox(
      width: double.infinity,
      height: 180,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (hasNewImage)
            Image.file(_newCoverImage!, fit: BoxFit.cover)
          else if (hasDefaultCover)
            Image.asset(_selectedDefaultCover!, fit: BoxFit.cover)
          else if (hasExistingImage)
            Image.network(
              _backgroundImageUrl!,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _buildDefaultBg(),
            )
          else
            _buildDefaultBg(),

          Container(color: Colors.black.withValues(alpha: 0.25)),

          // 중앙 버튼 2개
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: _pickCoverImage,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.photo_library, color: Colors.white, size: 18),
                        SizedBox(width: 6),
                        Text('갤러리', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: _showDefaultCoverPicker,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.image, color: Colors.white, size: 18),
                        SizedBox(width: 6),
                        Text('기본 이미지', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          if (hasNewImage || hasDefaultCover)
            Positioned(
              top: 12,
              right: 12,
              child: GestureDetector(
                onTap: () => setState(() {
                  _newCoverImage = null;
                  _selectedDefaultCover = null;
                }),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, color: Colors.white, size: 16),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDefaultBg() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
        ),
      ),
    );
  }

  void _showDefaultCoverPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 16),
              width: 36, height: 4,
              decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
            ),
            const Text(
              '기본 이미지 선택',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF191919)),
            ),
            const SizedBox(height: 16),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3, crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 1.3,
              ),
              itemCount: _defaultCovers.length,
              itemBuilder: (context, index) {
                final path = _defaultCovers[index];
                final isSelected = _selectedDefaultCover == path;
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedDefaultCover = path;
                      _newCoverImage = null;
                    });
                    Navigator.pop(context);
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: isSelected ? Border.all(color: const Color(0xFFFF7A7A), width: 3) : null,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(isSelected ? 9 : 12),
                      child: Image.asset(path, fit: BoxFit.cover),
                    ),
                  ),
                );
              },
            ),
            SizedBox(height: MediaQuery.of(context).padding.bottom),
          ],
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: const TextStyle(fontSize: 13, color: Color(0xFF888888), fontWeight: FontWeight.w500),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hintText,
    int maxLines = 1,
    int? maxLength,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      maxLength: maxLength,
      style: const TextStyle(fontSize: 15, color: Color(0xFF191919)),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: TextStyle(color: Colors.grey[400]),
        filled: true,
        fillColor: const Color(0xFFFAF8F5),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFECE8E4))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFECE8E4))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFFF7A7A))),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }
}
