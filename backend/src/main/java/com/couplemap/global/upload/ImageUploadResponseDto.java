package com.couplemap.global.upload;

import com.couplemap.global.s3.S3PresignedDto;
import lombok.Builder;
import lombok.Getter;

@Getter
@Builder
public class ImageUploadResponseDto {

    private final String uploadId;
    private final String fileKey;
    private final String url;

    public static ImageUploadResponseDto of(String uploadId, S3PresignedDto presigned) {
        return ImageUploadResponseDto.builder()
                .uploadId(uploadId)
                .fileKey(presigned.getFileKey())
                .url(presigned.getUrl())
                .build();
    }
}
