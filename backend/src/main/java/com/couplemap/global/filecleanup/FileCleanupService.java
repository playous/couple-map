package com.couplemap.global.filecleanup;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.List;

@Slf4j
@Service
@RequiredArgsConstructor
public class FileCleanupService {

    @Value("${file-cleanup.max-retry}")
    private int maxRetry;

    private final FileCleanupTaskRepository fileCleanupTaskRepository;
    private final FileCleanupTaskProcessor fileCleanupTaskProcessor;

    @Transactional
    public void scheduleDelete(String fileKey) {
        fileCleanupTaskRepository.save(FileCleanupTask.of(fileKey));
    }

    @Transactional
    public void scheduleDeleteAll(List<String> fileKeys) {
        fileCleanupTaskRepository.saveAll(
                fileKeys.stream().map(FileCleanupTask::of).toList()
        );
    }

    @Transactional
    public void schedulePendingUpload(List<String> fileKeys, LocalDateTime cleanupAfter) {
        if (fileKeys == null || fileKeys.isEmpty()) {
            return;
        }
        fileCleanupTaskRepository.saveAll(
                fileKeys.stream().map(key -> FileCleanupTask.ofPendingUpload(key, cleanupAfter)).toList()
        );
    }

    @Transactional
    public void cancelPendingUpload(List<String> fileKeys) {
        if (fileKeys == null || fileKeys.isEmpty()) {
            return;
        }
        fileCleanupTaskRepository.deleteByFileKeys(fileKeys);
    }

    @Scheduled(cron = "${file-cleanup.cron}")
    public void processPendingTasks() {
        List<Long> taskIds = fileCleanupTaskRepository.findPendingTaskIds(maxRetry, LocalDateTime.now());

        log.info("파일 정리 배치 시작: {}건", taskIds.size());

        for (Long taskId : taskIds) {
            fileCleanupTaskProcessor.process(taskId, maxRetry);
        }

        log.info("파일 정리 배치 완료");
    }
}
