import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../auth/domain/providers/auth_provider.dart';
import '../../data/models/memory_model.dart';
import '../../domain/providers/memory_provider.dart';

class MemoryEditScreen extends ConsumerStatefulWidget {
  final int mapId;
  final int memoryId;

  const MemoryEditScreen({
    super.key,
    required this.mapId,
    required this.memoryId,
  });

  @override
  ConsumerState<MemoryEditScreen> createState() => _MemoryEditScreenState();
}

class _MemoryEditScreenState extends ConsumerState<MemoryEditScreen> {
  static const int _titleMaxLength = 50;
  static const int _contentMaxLength = 100;
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _contentController = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  bool _isLoading = true;
  bool _isSaving = false;
  DateTime _selectedDate = DateTime.now();
  String? _selectedCategory;
  String? _placeName;
  String? _address;

  // 삭제할 기존 파일의 ID 목록
  final List<int> _deleteFileIds = [];

  // 기존 미디어 파일 (서버에서 가져온 것)
  List<MediaFile> _existingImages = [];
  List<MediaFile> _existingVideos = [];
  List<MediaFile> _existingAudios = [];

  // 새로 추가된 파일
  final List<File> _newImages = [];
  final List<File> _newVideos = [];
  final List<File> _newAudios = [];

  static const List<Map<String, dynamic>> _categories = [
    {'icon': Icons.restaurant, 'label': '음식점', 'color': Color(0xFFFF9800)},
    {'icon': Icons.coffee, 'label': '카페', 'color': Color(0xFF8D6E63)},
    {'icon': Icons.movie, 'label': '영화관', 'color': Color(0xFF7E57C2)},
    {'icon': Icons.shopping_bag, 'label': '쇼핑', 'color': Color(0xFF42A5F5)},
    {'icon': Icons.temple_buddhist, 'label': '관광지', 'color': Color(0xFF66BB6A)},
  ];

  @override
  void initState() {
    super.initState();
    _loadMemory();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _loadMemory() async {
    final auth = ref.read(authProvider);
    if (auth is! AuthSuccess) return;
    try {
      final memory = await ref.read(memoryRepositoryProvider).getMemoryDetail(
        widget.mapId,
        widget.memoryId,
      );
      if (mounted) {
        setState(() {
          _titleController.text = memory.title;
          _contentController.text = memory.content ?? '';
          _selectedDate = memory.memoryDate;
          _placeName = memory.placeName;
          _address = memory.address;
          _selectedCategory = memory.category;
          _existingImages = memory.mediaFiles
              .where((f) => f.fileType == MediaType.image)
              .toList();
          _existingVideos = memory.mediaFiles
              .where((f) => f.fileType == MediaType.video)
              .toList();
          _existingAudios = memory.mediaFiles
              .where((f) => f.fileType == MediaType.audio)
              .toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('로딩 실패: $e')));
      }
    }
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(primary: Color(0xFFFF7A7A)),
        ),
        child: child!,
      ),
    );
    if (date != null) setState(() => _selectedDate = date);
  }

  Future<void> _pickImages() async {
    final status = await Permission.photos.request();
    if (!status.isGranted && !status.isLimited) return;
    final picked = await _picker.pickMultiImage();
    if (!mounted || picked.isEmpty) return;
    setState(() {
      _newImages.addAll(picked.map((x) => File(x.path)));
    });
  }

  Future<void> _pickVideos() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      allowMultiple: true,
    );
    if (result == null || !mounted) return;
    setState(() {
      _newVideos.addAll(result.paths.whereType<String>().map((p) => File(p)));
    });
  }

  Future<void> _pickAudios() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      allowMultiple: true,
    );
    if (result == null || !mounted) return;
    setState(() {
      _newAudios.addAll(result.paths.whereType<String>().map((p) => File(p)));
    });
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    final content = _contentController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('제목을 입력해주세요')));
      return;
    }
    if (title.length > _titleMaxLength) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('제목은 50자 이하로 입력해주세요')),
      );
      return;
    }
    if (content.length > _contentMaxLength) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('내용은 100자 이하로 입력해주세요')),
      );
      return;
    }
    final auth = ref.read(authProvider);
    if (auth is! AuthSuccess) return;

    setState(() => _isSaving = true);
    try {
      final requestData = {
        'title': title,
        'content': content,
        if (_placeName != null) 'placeName': _placeName,
        if (_selectedCategory != null) 'category': _selectedCategory,
        'memoryDate': _selectedDate.toIso8601String().split('T').first,
        if (_deleteFileIds.isNotEmpty) 'deleteFileIds': _deleteFileIds,
      };

      final allNewFiles = <File>[
        ..._newImages,
        ..._newVideos,
        ..._newAudios,
      ];

      await ref.read(memoryRepositoryProvider).updateMemory(
        widget.mapId,
        widget.memoryId,
        requestData,
        allNewFiles.isNotEmpty ? allNewFiles : null,
      );
      if (mounted) context.pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('오류: ${e.toString()}')));
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
          '추억 수정',
          style: TextStyle(
            color: Color(0xFF191919),
            fontSize: 18,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
        ),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _save,
            child: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFFFF7A7A),
                    ),
                  )
                : const Text(
                    '저장',
                    style: TextStyle(
                      color: Color(0xFFFF7A7A),
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFFF7A7A)))
          : Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 장소 카드
                        _buildPlaceCard(),
                        const SizedBox(height: 20),

                        // 카테고리
                        _buildSectionLabel('카테고리'),
                        const SizedBox(height: 10),
                        _buildCategoryChips(),
                        const SizedBox(height: 24),

                        // 제목
                        _buildSectionLabel('제목'),
                        const SizedBox(height: 8),
                        _buildTextField(
                          controller: _titleController,
                          hintText: '추억의 제목을 적어주세요',
                          maxLines: 1,
                          maxLength: _titleMaxLength,
                        ),
                        const SizedBox(height: 24),

                        // 내용
                        _buildSectionLabel('내용'),
                        const SizedBox(height: 8),
                        _buildTextField(
                          controller: _contentController,
                          hintText: '어떤 하루였나요?',
                          maxLines: 4,
                          maxLength: _contentMaxLength,
                        ),
                        const SizedBox(height: 24),

                        // 날짜
                        _buildSectionLabel('날짜'),
                        const SizedBox(height: 8),
                        _buildDatePicker(),
                        const SizedBox(height: 24),

                        // 사진 · 동영상
                        _buildMediaCountLabel(),
                        const SizedBox(height: 10),
                        _buildMediaSection(),
                        const SizedBox(height: 24),

                        // 오디오
                        _buildAudioCountLabel(),
                        const SizedBox(height: 10),
                        _buildAudioSection(),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ),
                _buildBottomButton(),
              ],
            ),
    );
  }

  Widget _buildPlaceCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFECE8E4)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(
              color: Color(0xFFFFF0F0),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.place, size: 18, color: Color(0xFFFF7A7A)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _placeName ?? '장소를 선택해주세요',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF191919),
                  ),
                ),
                if (_address != null && _address!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    _address!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF999999),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String label) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 13,
        color: Color(0xFF888888),
        fontWeight: FontWeight.w500,
      ),
    );
  }

  Widget _buildMediaCountLabel() {
    final totalCount = _existingImages.length +
        _existingVideos.length +
        _newImages.length +
        _newVideos.length;
    return Row(
      children: [
        _buildSectionLabel('사진 · 동영상'),
        if (totalCount > 0) ...[
          const SizedBox(width: 6),
          Text(
            '$totalCount',
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFFFF7A7A),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildAudioCountLabel() {
    final totalCount = _existingAudios.length + _newAudios.length;
    return Row(
      children: [
        _buildSectionLabel('오디오'),
        if (totalCount > 0) ...[
          const SizedBox(width: 6),
          Text(
            '$totalCount',
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFFFF7A7A),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildCategoryChips() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _categories.map((cat) {
        final isSelected = _selectedCategory == cat['label'];
        return GestureDetector(
          onTap: () => setState(() {
            _selectedCategory = isSelected ? null : cat['label'] as String;
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
                Icon(
                  cat['icon'] as IconData,
                  size: 16,
                  color: cat['color'] as Color,
                ),
                const SizedBox(width: 6),
                Text(
                  cat['label'] as String,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected
                        ? const Color(0xFFFF7A7A)
                        : const Color(0xFF888888),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hintText,
    int maxLines = 1,
    int? maxLength,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFECE8E4)),
      ),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        maxLength: maxLength,
        style: const TextStyle(fontSize: 15, color: Color(0xFF191919)),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: const TextStyle(color: Color(0xFFBBBBBB), fontSize: 15),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    );
  }

  Widget _buildDatePicker() {
    return GestureDetector(
      onTap: _pickDate,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFECE8E4)),
        ),
        child: Text(
          '${_selectedDate.year}. '
          '${_selectedDate.month.toString().padLeft(2, '0')}. '
          '${_selectedDate.day.toString().padLeft(2, '0')}',
          style: const TextStyle(fontSize: 15, color: Color(0xFF191919)),
        ),
      ),
    );
  }

  Widget _buildMediaSection() {
    final allMedia = <Widget>[];

    // 기존 이미지 (서버)
    for (int i = 0; i < _existingImages.length; i++) {
      allMedia.add(_buildNetworkMediaThumbnail(
        imageUrl: _existingImages[i].fileUrl,
        onRemove: () => setState(() {
          _deleteFileIds.add(_existingImages[i].mediaFileId);
          _existingImages.removeAt(i);
        }),
      ));
    }

    // 기존 비디오 (서버)
    for (int i = 0; i < _existingVideos.length; i++) {
      allMedia.add(_buildVideoThumbnail(
        isNetwork: true,
        onRemove: () => setState(() {
          _deleteFileIds.add(_existingVideos[i].mediaFileId);
          _existingVideos.removeAt(i);
        }),
      ));
    }

    // 새 이미지
    for (int i = 0; i < _newImages.length; i++) {
      allMedia.add(_buildFileMediaThumbnail(
        file: _newImages[i],
        onRemove: () => setState(() => _newImages.removeAt(i)),
      ));
    }

    // 새 비디오
    for (int i = 0; i < _newVideos.length; i++) {
      allMedia.add(_buildVideoThumbnail(
        isNetwork: false,
        onRemove: () => setState(() => _newVideos.removeAt(i)),
      ));
    }

    // 추가 버튼
    allMedia.add(
      GestureDetector(
        onTap: _showMediaPickerOptions,
        child: Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFCCCCCC)),
          ),
          child: const Center(
            child: Icon(Icons.add, size: 28, color: Color(0xFFBBBBBB)),
          ),
        ),
      ),
    );

    return Wrap(spacing: 8, runSpacing: 8, children: allMedia);
  }

  Widget _buildNetworkMediaThumbnail({
    required String imageUrl,
    required VoidCallback onRemove,
  }) {
    return SizedBox(
      width: 80,
      height: 80,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              imageUrl,
              width: 80,
              height: 80,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: 80,
                height: 80,
                color: const Color(0xFFF0ECE8),
                child: const Icon(Icons.broken_image, color: Color(0xFFBBBBBB)),
              ),
            ),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, size: 14, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFileMediaThumbnail({
    required File file,
    required VoidCallback onRemove,
  }) {
    return SizedBox(
      width: 80,
      height: 80,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(file, width: 80, height: 80, fit: BoxFit.cover),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, size: 14, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoThumbnail({
    required bool isNetwork,
    required VoidCallback onRemove,
  }) {
    return SizedBox(
      width: 80,
      height: 80,
      child: Stack(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: const Color(0xFFD5E8D4),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(
              child: Icon(Icons.play_circle_fill, size: 32, color: Colors.white),
            ),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, size: 14, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showMediaPickerOptions() {
    FocusScope.of(context).unfocus();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        margin: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(context).padding.bottom + 16),
        decoration: BoxDecoration(
          color: const Color(0xFFFAF8F5),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 12),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFDDD8D3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            _buildPickerOption(
              icon: Icons.photo_library_rounded,
              label: '사진 선택',
              subtitle: '갤러리에서 사진을 가져와요',
              onTap: () { Navigator.pop(context); _pickImages(); },
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Divider(height: 1, color: const Color(0xFFECE8E4)),
            ),
            _buildPickerOption(
              icon: Icons.videocam_rounded,
              label: '동영상 선택',
              subtitle: '갤러리에서 동영상을 가져와요',
              onTap: () { Navigator.pop(context); _pickVideos(); },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildPickerOption({
    required IconData icon,
    required String label,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF0F0),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: const Color(0xFFFF7A7A), size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF2C2C2C),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF999999),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Color(0xFFCCCCCC), size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAudioSection() {
    return Column(
      children: [
        // 기존 오디오 (서버)
        ..._existingAudios.asMap().entries.map((entry) {
          final index = entry.key;
          final audio = entry.value;
          return _buildAudioItem(
            label: audio.originalFilename,
            onRemove: () => setState(() {
              _deleteFileIds.add(audio.mediaFileId);
              _existingAudios.removeAt(index);
            }),
          );
        }),

        // 새 오디오
        ..._newAudios.asMap().entries.map((entry) {
          final index = entry.key;
          final file = entry.value;
          final fileName = file.path.split('/').last.split('\\').last;
          return _buildAudioItem(
            label: fileName,
            onRemove: () => setState(() => _newAudios.removeAt(index)),
          );
        }),

        // 추가 버튼
        GestureDetector(
          onTap: _pickAudios,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFCCCCCC)),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add, size: 18, color: Color(0xFFBBBBBB)),
                SizedBox(width: 6),
                Text(
                  '오디오 추가',
                  style: TextStyle(
                    fontSize: 14,
                    color: Color(0xFFBBBBBB),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAudioItem({required String label, required VoidCallback onRemove}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFECE8E4)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(
              color: Color(0xFFFF7A7A),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.play_arrow, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          GestureDetector(
            onTap: onRemove,
            child: const Icon(Icons.close, size: 18, color: Color(0xFF888888)),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomButton() {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20, 12, 20,
        MediaQuery.of(context).padding.bottom + 20,
      ),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton(
          onPressed: _isSaving ? null : _save,
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
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                )
              : const Text(
                  '추억 수정',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
        ),
      ),
    );
  }
}
