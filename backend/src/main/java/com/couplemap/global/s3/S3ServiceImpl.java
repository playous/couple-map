package com.couplemap.global.s3;

import com.couplemap.global.exception.exceptions.S3Exception;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.DeleteObjectRequest;
import software.amazon.awssdk.services.s3.model.GetObjectRequest;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;
import software.amazon.awssdk.services.s3.presigner.S3Presigner;
import software.amazon.awssdk.services.s3.presigner.model.GetObjectPresignRequest;
import software.amazon.awssdk.services.s3.presigner.model.PutObjectPresignRequest;

import java.time.Duration;
import java.util.Set;
import java.util.UUID;

import static com.couplemap.global.exception.code.S3ErrorCode.*;

@Slf4j
@Service
@RequiredArgsConstructor
public class S3ServiceImpl implements S3Service {

    private static final String PROFILE_DIR = "profile";
    private static final String MEMORY_DIR = "memory";
    private static final long MAX_IMAGE_FILE_SIZE = 5 * 1024 * 1024; // 5MB
    private static final long MAX_MEDIA_FILE_SIZE = 100 * 1024 * 1024; // 100MB
    private static final Set<String> ALLOWED_PROFILE_CONTENT_TYPES = Set.of(
            "image/jpeg",
            "image/jpg",
            "image/png"
    );
    private static final Set<String> ALLOWED_PROFILE_EXTENSIONS = Set.of(
            "jpeg",
            "jpg",
            "png"
    );
    private static final Set<String> ALLOWED_MEDIA_CONTENT_TYPES = Set.of(
            "image/jpeg", "image/jpg", "image/png",
            "video/mp4", "video/quicktime",
            "audio/mpeg", "audio/mp4", "audio/x-m4a"
    );
    private static final Set<String> ALLOWED_MEDIA_EXTENSIONS = Set.of(
            "jpg", "jpeg", "png",
            "mp4", "mov",
            "mp3", "m4a"
    );

    private final S3Client s3Client;
    private final S3Presigner s3Presigner;

    @Value("${spring.cloud.aws.s3.bucket}")
    private String bucket;
    @Value("${spring.cloud.aws.region.static}")
    private String region;
    @Value("${spring.cloud.aws.s3.key-prefix:}")
    private String keyPrefix;
    @Value("${upload.presign.put-ttl}")
    private Duration putTtl;
    @Value("${upload.presign.get-ttl}")
    private Duration getTtl;

    @Override
    public S3PresignedDto presignMediaUpload(String filename, String contentType, long size) {
        String ext = validateSpec(filename, contentType, size,
                MAX_MEDIA_FILE_SIZE, ALLOWED_MEDIA_CONTENT_TYPES, ALLOWED_MEDIA_EXTENSIONS);
        return presignPut(createFileName(MEMORY_DIR, ext), contentType, size);
    }

    @Override
    public S3PresignedDto presignImageUpload(String filename, String contentType, long size) {
        String ext = validateSpec(filename, contentType, size,
                MAX_IMAGE_FILE_SIZE, ALLOWED_PROFILE_CONTENT_TYPES, ALLOWED_PROFILE_EXTENSIONS);
        return presignPut(createFileName(PROFILE_DIR, ext), contentType, size);
    }

    private S3PresignedDto presignPut(String fileKey, String contentType, long size) {
        // contentType·contentLength를 서명에 포함해 S3가 위반을 거부하게 한다
        PutObjectRequest putObjectRequest = PutObjectRequest.builder()
                .bucket(bucket)
                .key(fileKey)
                .contentType(contentType)
                .contentLength(size)
                .build();

        try {
            PutObjectPresignRequest presignRequest = PutObjectPresignRequest.builder()
                    .signatureDuration(putTtl)
                    .putObjectRequest(putObjectRequest)
                    .build();

            String url = s3Presigner.presignPutObject(presignRequest).url().toString();

            return S3PresignedDto.builder()
                    .fileKey(fileKey)
                    .url(url)
                    .build();
        } catch (Exception e) {
            log.error("presigned URL 발급 실패: {}", e.getMessage());
            throw new S3Exception(S3_PRESIGN_FAILED);
        }
    }

    public void deleteFile(String deleteKey) {
        try {
            DeleteObjectRequest deleteObjectRequest = DeleteObjectRequest.builder()
                    .bucket(bucket)
                    .key(deleteKey)
                    .build();

            s3Client.deleteObject(deleteObjectRequest);
            log.info("S3 파일 삭제 성공: {}", deleteKey);
        } catch (Exception e) {
            log.error("S3 파일 삭제 실패: {}", e.getMessage());
            throw new S3Exception(S3_DELETE_FAILED);
        }
    }

    private String createFileName(String dirName, String ext) {
        String uuid = UUID.randomUUID().toString();
        String fileName = dirName + "/" + uuid + "." + ext;
        return keyPrefix.isEmpty() ? fileName : keyPrefix + fileName;
    }

    private String extractExt(String originalFileName,  Set<String> allowedExtensions) {
        int pos = originalFileName.lastIndexOf(".");
        if (pos == -1) {
            throw new S3Exception(INVALID_FILE_EXTENSION);
        }
        String ext = originalFileName.substring(pos + 1).toLowerCase();

        if (!allowedExtensions.contains(ext)) {
            throw new S3Exception(INVALID_FILE_TYPE);
        }
        return ext;
    }

    // 버킷 비공개 후로는 열리지 않는다. NOT NULL 컬럼을 채우기 위해서만 남겨둔 값
    private String directUrl(String fileKey) {
        return String.format("https://%s.s3.%s.amazonaws.com/%s", bucket, region, fileKey);
    }

    // 버킷이 비공개라 직링크로는 못 읽는다. 조회 시점에 서명해서 내려준다
    @Override
    public String getFileUrl(String fileKey) {
        if (fileKey == null) {
            return null;
        }

        GetObjectRequest getObjectRequest = GetObjectRequest.builder()
                .bucket(bucket)
                .key(fileKey)
                .build();

        GetObjectPresignRequest presignRequest = GetObjectPresignRequest.builder()
                .signatureDuration(getTtl)
                .getObjectRequest(getObjectRequest)
                .build();

        return s3Presigner.presignGetObject(presignRequest).url().toString();
    }

    // presigned 경로용 검증 — 서버가 파일을 받지 않으므로 클라이언트가 신고한 값으로 검사한다
    private String validateSpec(String filename, String contentType, long size,
                                long maxSize, Set<String> allowedTypes, Set<String> allowedExtensions) {
        if (filename == null || filename.isEmpty() || !filename.contains(".")) {
            throw new S3Exception(INVALID_FILE_NAME);
        }
        if (contentType == null || !allowedTypes.contains(contentType)) {
            throw new S3Exception(INVALID_FILE_TYPE);
        }
        if (size <= 0 || size > maxSize) {
            throw new S3Exception(FILE_SIZE_EXCEEDED);
        }
        return extractExt(filename, allowedExtensions);
    }
}