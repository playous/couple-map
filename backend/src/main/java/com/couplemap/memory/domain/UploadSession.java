package com.couplemap.memory.domain;

import jakarta.persistence.Id;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;
import org.springframework.data.redis.core.RedisHash;
import org.springframework.data.redis.core.TimeToLive;

import java.util.List;
import java.util.Optional;

@RedisHash(value = "uploadSession")
@Builder
@Getter
public class UploadSession {

    public static final String PURPOSE_MEMORY = "MEMORY";
    public static final String PURPOSE_IMAGE = "IMAGE";

    // 지도와 무관한 업로드(프로필 등)를 표시하는 값
    public static final long NO_MAP = 0L;

    @Id
    private final String id;

    private final Long userId;
    private final Long mapId;
    private final String purpose;
    private final List<UploadFile> files;

    @TimeToLive
    private final Long expiration;

    public static UploadSession of(String uploadId, Long userId, Long mapId, String purpose,
                                   List<UploadFile> files, long ttlSeconds) {
        return UploadSession.builder()
                .id(uploadId)
                .userId(userId)
                .mapId(mapId)
                .purpose(purpose)
                .files(files)
                .expiration(ttlSeconds)
                .build();
    }

    public boolean isOwnedBy(Long userId, Long mapId) {
        return this.userId.equals(userId) && this.mapId.equals(mapId);
    }

    public boolean isImageOwnedBy(Long userId) {
        return PURPOSE_IMAGE.equals(this.purpose) && this.userId.equals(userId);
    }

    public Optional<UploadFile> find(String fileKey) {
        return files.stream().filter(f -> f.getFileKey().equals(fileKey)).findFirst();
    }

    public List<String> fileKeys() {
        return files.stream().map(UploadFile::getFileKey).toList();
    }

    @Getter
    @Setter
    @NoArgsConstructor
    @AllArgsConstructor
    public static class UploadFile {
        private String fileKey;
        private String filename;
        private String contentType;
        private Long size;
    }
}
