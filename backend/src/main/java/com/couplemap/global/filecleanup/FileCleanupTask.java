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
@Table(name = "file_cleanup_task",
        indexes = @Index(name = "idx_cleanup_status", columnList = "status")
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
