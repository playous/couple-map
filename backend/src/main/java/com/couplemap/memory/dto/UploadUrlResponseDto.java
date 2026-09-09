package com.couplemap.memory.dto;

import com.couplemap.global.s3.S3PresignedDto;
import lombok.Builder;
import lombok.Getter;

import java.util.List;

@Getter
@Builder
public class UploadUrlResponseDto {

    private final String uploadId;
    private final List<Item> items;

    public static UploadUrlResponseDto of(String uploadId, List<S3PresignedDto> presigned) {
        return UploadUrlResponseDto.builder()
                .uploadId(uploadId)
                .items(presigned.stream()
                        .map(p -> new Item(p.getFileKey(), p.getUrl()))
                        .toList())
                .build();
    }

    @Getter
    public static class Item {

        private final String fileKey;
        private final String url;

        public Item(String fileKey, String url) {
            this.fileKey = fileKey;
            this.url = url;
        }
    }
}
