package com.couplemap.global.filecleanup;

import jakarta.persistence.*;
import lombok.AccessLevel;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;

import java.time.LocalDateTime;

@Entity
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
// file_key 인덱스가 없으면 업로드 완료 시의 예약 취소 DELETE가 조건에 맞는 행을 전부 훑으며
// 다른 요청의 행까지 잠가 데드락이 난다
@Table(name = "file_cleanup_task",
        indexes = {
                @Index(name = "idx_cleanup_status", columnList = "status"),
                @Index(name = "idx_cleanup_file_key", columnList = "file_key")
        }
)

public class FileCleanupTask {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "file_key", nullable = false, length = 300)
    private String fileKey;

    @Enumerated(EnumType.STRING)
    @Column(name = "status", nullable = false)
    private FileCleanupStatus status;

    @Column(name = "retry_count", nullable = false)
    private int retryCount;

    @Column(name = "next_retry_at")
    private LocalDateTime nextRetryAt;

    @Column(name = "last_error", length = 500)
    private String lastError;

    @Column(name = "created_at", nullable = false, updatable = false)
    private LocalDateTime createdAt;

    @Builder
    private FileCleanupTask(String fileKey) {
        this.fileKey = fileKey;
        this.status = FileCleanupStatus.PENDING;
        this.retryCount = 0;
        this.createdAt = LocalDateTime.now();
        this.nextRetryAt = LocalDateTime.now(); // null 방지용
    }

    public static FileCleanupTask of(String fileKey) {
        return FileCleanupTask.builder()
                .fileKey(fileKey)
                .build();
    }

    // 발급 직후 등록해 두고 완료 통보가 오면 취소한다. 안 오면 유예 시간 뒤 배치가 회수한다
    public static FileCleanupTask ofPendingUpload(String fileKey, LocalDateTime cleanupAfter) {
        FileCleanupTask task = new FileCleanupTask(fileKey);
        task.nextRetryAt = cleanupAfter;
        return task;
    }

    public void markDone() {
        this.status = FileCleanupStatus.DONE;
    }

    public void markFailed(String error, int maxRetry) {
        this.retryCount++;
        this.lastError = error;
        if (this.retryCount >= maxRetry) {
            this.status = FileCleanupStatus.FAILED;
        } else {
            this.nextRetryAt = LocalDateTime.now().plusDays(1).plusMinutes(30);
        }
    }
}
