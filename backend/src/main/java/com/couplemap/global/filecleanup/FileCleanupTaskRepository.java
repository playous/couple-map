package com.couplemap.global.filecleanup;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.time.LocalDateTime;
import java.util.List;

@Repository
public interface FileCleanupTaskRepository extends JpaRepository<FileCleanupTask, Long> {

    @Query("SELECT t.id FROM FileCleanupTask t WHERE t.status = 'PENDING' " +
            "AND t.retryCount < :maxRetry " +
            "AND t.nextRetryAt <= :now")
    List<Long> findPendingTaskIds(int maxRetry, LocalDateTime now);

    @Modifying(flushAutomatically = true)
    @Query("DELETE FROM FileCleanupTask t WHERE t.fileKey IN :fileKeys AND t.status = 'PENDING'")
    void deleteByFileKeys(@Param("fileKeys") List<String> fileKeys);
}
