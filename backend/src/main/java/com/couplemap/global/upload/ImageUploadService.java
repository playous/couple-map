package com.couplemap.global.upload;

import com.couplemap.global.exception.code.S3ErrorCode;
import com.couplemap.global.exception.exceptions.S3Exception;
import com.couplemap.global.filecleanup.FileCleanupService;
import com.couplemap.global.s3.S3PresignedDto;
import com.couplemap.global.s3.S3Service;
import com.couplemap.memory.domain.UploadSession;
import com.couplemap.memory.repository.UploadSessionRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Duration;
import java.time.LocalDateTime;
import java.util.List;
import java.util.UUID;

// 프로필 이미지와 지도 배경처럼 지도에 속하지 않는 단일 이미지 업로드를 담당한다
@Service
@RequiredArgsConstructor
public class ImageUploadService {

    private final S3Service s3Service;
    private final UploadSessionRepository uploadSessionRepository;
    private final FileCleanupService fileCleanupService;

    @Value("${upload.session-ttl}")
    private Duration sessionTtl;
    @Value("${upload.orphan-grace}")
    private Duration orphanGrace;

    @Transactional
    public ImageUploadResponseDto issue(ImageUploadRequestDto request, Long userId) {
        S3PresignedDto presigned = s3Service.presignImageUpload(
                request.getFilename(), request.getContentType(), request.getSize());

        String uploadId = UUID.randomUUID().toString();
        UploadSession.UploadFile file = new UploadSession.UploadFile(
                presigned.getFileKey(), request.getFilename(), request.getContentType(), request.getSize());

        uploadSessionRepository.save(UploadSession.of(
                uploadId, userId, UploadSession.NO_MAP, UploadSession.PURPOSE_IMAGE,
                List.of(file), sessionTtl.toSeconds()));

        fileCleanupService.schedulePendingUpload(
                List.of(presigned.getFileKey()), LocalDateTime.now().plus(orphanGrace));

        return ImageUploadResponseDto.of(uploadId, presigned);
    }

    // 발급한 세션이 맞는지 확인하고 회수 예약을 푼다. 실제 저장은 호출한 도메인이 한다
    @Transactional
    public String consume(String uploadId, String fileKey, Long userId) {
        UploadSession session = uploadSessionRepository.findById(uploadId)
                .orElseThrow(() -> new S3Exception(S3ErrorCode.UPLOAD_SESSION_NOT_FOUND));

        if (!session.isImageOwnedBy(userId)) {
            throw new S3Exception(S3ErrorCode.UPLOAD_SESSION_MISMATCH);
        }
        session.find(fileKey)
                .orElseThrow(() -> new S3Exception(S3ErrorCode.UPLOAD_SESSION_MISMATCH));

        fileCleanupService.cancelPendingUpload(List.of(fileKey));
        uploadSessionRepository.deleteById(uploadId);

        return fileKey;
    }
}
