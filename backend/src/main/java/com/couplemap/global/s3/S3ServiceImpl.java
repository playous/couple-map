package com.couplemap.global.s3;

import com.couplemap.global.exception.exceptions.S3Exception;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;
import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.DeleteObjectRequest;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;

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

    @Value("${spring.cloud.aws.s3.bucket}")
    private String bucket;
    @Value("${spring.cloud.aws.region.static}")
    private String region;
    @Value("${spring.cloud.aws.s3.key-prefix:}")
    private String keyPrefix;

    public S3UploadDto uploadImageFile(MultipartFile file) {
        String ext = validateFile(file, MAX_IMAGE_FILE_SIZE, ALLOWED_PROFILE_CONTENT_TYPES, ALLOWED_PROFILE_EXTENSIONS);
        return upload(file, createFileName(PROFILE_DIR, ext));
    }

    public S3UploadDto uploadMediaFile(MultipartFile file) {
        String ext = validateFile(file, MAX_MEDIA_FILE_SIZE, ALLOWED_MEDIA_CONTENT_TYPES, ALLOWED_MEDIA_EXTENSIONS);
        return upload(file, createFileName(MEMORY_DIR, ext));
    }

    private S3UploadDto upload(MultipartFile file, String fileName) {
        try {
            PutObjectRequest putObjectRequest = PutObjectRequest.builder()
                    .bucket(bucket)
                    .key(fileName)
                    .contentType(file.getContentType())
                    .build();

            s3Client.putObject(putObjectRequest,
                    RequestBody.fromInputStream(file.getInputStream(), file.getSize()));

            return S3UploadDto.builder()
                    .url(getFileUrl(fileName))
                    .key(fileName)
                    .build();

        } catch (Exception e) {
            log.error("S3 파일 업로드 실패: {}", e.getMessage());
            throw new S3Exception(S3_UPLOAD_FAILED);
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

    private String getFileUrl(String fileName) {
        return String.format("https://%s.s3.%s.amazonaws.com/%s", bucket, region, fileName);
    }

    private String validateFile(MultipartFile file, long maxSize, Set<String> allowedTypes, Set<String> allowedExtensions){
        checkNull(file);
        checkSize(file, maxSize);
        checkContentType(file, allowedTypes);
        return checkFileExtension(file, allowedExtensions);
    }

    private void checkNull(MultipartFile file) {
        if (file == null || file.isEmpty()) {
            throw new S3Exception(FILE_IS_EMPTY);
        }
    }

    private void checkSize(MultipartFile file, long maxSize) {
        if (file.getSize() > maxSize) {
            throw new S3Exception(FILE_SIZE_EXCEEDED);
        }
    }
    private void checkContentType(MultipartFile file, Set<String> allowedTypes) {
        String contentType = file.getContentType();
        if (contentType == null || !allowedTypes.contains(contentType)) {
            throw new S3Exception(INVALID_FILE_TYPE);
        }
    }

    private String checkFileExtension(MultipartFile file, Set<String> allowedExtensions) {
        String originalFilename = file.getOriginalFilename();

        if (originalFilename == null || originalFilename.isEmpty()) {
            throw new S3Exception(INVALID_FILE_NAME);
        }

        if (!originalFilename.contains(".")) {
            throw new S3Exception(INVALID_FILE_NAME);
        }

        return extractExt(originalFilename, allowedExtensions);
    }

}