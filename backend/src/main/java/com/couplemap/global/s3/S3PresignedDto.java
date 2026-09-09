package com.couplemap.global.s3;

import lombok.Builder;
import lombok.Getter;

@Getter
@Builder
public class S3PresignedDto {

    private final String fileKey;
    private final String url;
}
