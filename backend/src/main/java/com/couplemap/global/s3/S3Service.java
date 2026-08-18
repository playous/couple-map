package com.couplemap.global.s3;

public interface S3Service {

    void deleteFile(String deleteKey);

    // 클라이언트가 S3에 직접 PUT 할 수 있는 서명 URL을 발급한다
    S3PresignedDto presignMediaUpload(String filename, String contentType, long size);
    S3PresignedDto presignImageUpload(String filename, String contentType, long size);

    // 버킷이 비공개라 조회도 서명이 필요하다
    String getFileUrl(String fileKey);
}
