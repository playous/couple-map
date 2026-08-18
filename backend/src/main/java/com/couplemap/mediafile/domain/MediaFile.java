package com.couplemap.mediafile.domain;

import com.couplemap.global.common.BaseEntity;
import com.couplemap.memory.domain.Memory;
import jakarta.persistence.*;
import lombok.AccessLevel;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;

@Entity
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@Table(name = "media_files")
public class MediaFile extends BaseEntity {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "media_file_id")
    private Long mediaFileId;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "memory_id", nullable = false)
    private Memory memory;

    // 접근, 삭제 모두 이 키로 한다. URL은 조회 시점에 서명해서 만들고 저장하지 않는다
    @Column(name = "file_key", nullable = false, length = 300)
    private String fileKey;

    @Column(name = "original_filename", length = 255)
    private String originalFilename;

    @Enumerated(EnumType.STRING)
    @Column(name = "media_file_type", nullable = false)
    private MediaFileType mediaFileType;  // IMAGE, VIDEO , AUDIO

    @Column(name = "file_size")
    private Long fileSize;

    @Column(name = "display_order")
    private Integer displayOrder;

    @Builder
    private MediaFile(Memory memory, String fileKey, String originalFilename, MediaFileType mediaFileType, Long fileSize, Integer displayOrder) {
        this.memory = memory;
        this.fileKey = fileKey;
        this.originalFilename = originalFilename;
        this.mediaFileType = mediaFileType;
        this.fileSize = fileSize;
        this.displayOrder = displayOrder;
    }

    public static MediaFile of(Memory memory, String fileKey, String originalFilename,
                               MediaFileType type, Long fileSize, int order) {
        return MediaFile.builder()
                .memory(memory)
                .fileKey(fileKey)
                .originalFilename(originalFilename)
                .mediaFileType(type)
                .fileSize(fileSize)
                .displayOrder(order)
                .build();
    }
}
