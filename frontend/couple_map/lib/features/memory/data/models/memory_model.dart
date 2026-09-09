// 기존 lib/models/memory/ 에서 이식

enum MediaType { image, video, audio }

class MediaFile {
  final int mediaFileId;
  final String fileUrl;
  final String originalFilename;
  final MediaType fileType;
  final int fileSize;
  final int displayOrder;

  const MediaFile({
    required this.mediaFileId,
    required this.fileUrl,
    required this.originalFilename,
    required this.fileType,
    required this.fileSize,
    required this.displayOrder,
  });

  factory MediaFile.fromJson(Map<String, dynamic> json) {
    return MediaFile(
      mediaFileId: json['mediaFileId'] as int,
      fileUrl: json['fileUrl'] as String,
      originalFilename: json['originalFilename'] as String,
      fileType: MediaType.values.firstWhere(
        (e) => e.name.toUpperCase() == json['mediaFileType'],
        orElse: () => MediaType.image,
      ),
      fileSize: json['fileSize'] as int,
      displayOrder: json['displayOrder'] as int,
    );
  }
}

class MemoryModel {
  final int memoryId;
  final String title;
  final String? content;
  final String placeName;
  final String? address;
  final String? category;
  final DateTime memoryDate;
  final double latitude;
  final double longitude;
  final List<MediaFile> mediaFiles;

  const MemoryModel({
    required this.memoryId,
    required this.title,
    this.content,
    required this.placeName,
    this.address,
    this.category,
    required this.memoryDate,
    required this.latitude,
    required this.longitude,
    required this.mediaFiles,
  });

  factory MemoryModel.fromJson(Map<String, dynamic> json) {
    return MemoryModel(
      memoryId: json['memoryId'] as int,
      title: json['title'] as String,
      content: json['content'] as String?,
      placeName: json['placeName'] as String,
      address: json['address'] as String?,
      category: json['category'] as String?,
      memoryDate: DateTime.parse(json['memoryDate'] as String),
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      mediaFiles: (json['mediaFiles'] as List?)
              ?.map((f) => MediaFile.fromJson(f as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

class MemorySummary {
  final int memoryId;
  final String title;
  final String placeName;
  final String? category;
  final double latitude;
  final double longitude;
  final DateTime? memoryDate;
  final String? thumbnailUrl;

  const MemorySummary({
    required this.memoryId,
    required this.title,
    required this.placeName,
    this.category,
    required this.latitude,
    required this.longitude,
    this.memoryDate,
    this.thumbnailUrl,
  });

  factory MemorySummary.fromJson(Map<String, dynamic> json) {
    return MemorySummary(
      memoryId: json['memoryId'] as int,
      title: json['title'] as String,
      placeName: json['placeName'] as String,
      category: json['category'] as String?,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      memoryDate: json['memoryDate'] != null
          ? DateTime.parse(json['memoryDate'] as String)
          : null,
      thumbnailUrl: json['thumbnailUrl'] as String?,
    );
  }
}

class MemoryMarker {
  final int memoryId;
  final String? category;
  final double latitude;
  final double longitude;
  final DateTime? memoryDate;

  const MemoryMarker({
    required this.memoryId,
    this.category,
    required this.latitude,
    required this.longitude,
    this.memoryDate,
  });

  factory MemoryMarker.fromJson(Map<String, dynamic> json) {
    return MemoryMarker(
      memoryId: json['memoryId'] as int,
      category: json['category'] as String?,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      memoryDate: json['memoryDate'] != null
          ? DateTime.parse(json['memoryDate'] as String)
          : null,
    );
  }
}
