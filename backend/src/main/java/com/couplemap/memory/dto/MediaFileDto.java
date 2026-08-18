package com.couplemap.memory.dto;

import com.couplemap.mediafile.domain.MediaFile;
import com.couplemap.mediafile.domain.MediaFileType;
import lombok.Getter;

@Getter
public class MediaFileDto {
    private final Long mediaFileId;
    private final String fileUrl;
    private final String originalFilename;
    private final MediaFileType mediaFileType;
    private final Long fileSize;
    private final Integer displayOrder;

    // URL은 file_key로 응답 시점에 만든다. 저장된 file_url을 읽으면 도메인이 데이터에 박혀
    // CloudFront 전환 때 전 행을 마이그레이션해야 한다
    public MediaFileDto(MediaFile mediaFile, String fileUrl) {
        this.mediaFileId = mediaFile.getMediaFileId();
        this.fileUrl = fileUrl;
        this.originalFilename = mediaFile.getOriginalFilename();
        this.mediaFileType = mediaFile.getMediaFileType();
        this.fileSize = mediaFile.getFileSize();
        this.displayOrder = mediaFile.getDisplayOrder();
    }
}
