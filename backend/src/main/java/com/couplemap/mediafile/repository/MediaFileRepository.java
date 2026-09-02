package com.couplemap.mediafile.repository;

import com.couplemap.mediafile.domain.MediaFile;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.util.List;

@Repository
public interface MediaFileRepository extends JpaRepository<MediaFile, Long> {

    @Query("SELECT mf FROM MediaFile mf WHERE mf.memory.memoryId = :memoryId")
    List<MediaFile> findByMemoryId(@Param("memoryId") Long memoryId);

    @Query("SELECT mf FROM MediaFile mf WHERE mf.memory.memoryId = :memoryId ORDER BY mf.displayOrder ASC")
    List<MediaFile> findByMemoryIdOrderByDisplayOrder(@Param("memoryId") Long memoryId);

    // 목록, 캘린더 썸네일용. 추억당 displayOrder 최소 1장만 반환해 불필요한 행 로딩을 막는다
    @Query("SELECT mf FROM MediaFile mf " +
            "WHERE mf.memory.memoryId IN :memoryIds " +
            "AND mf.displayOrder = (SELECT MIN(mf2.displayOrder) FROM MediaFile mf2 WHERE mf2.memory = mf.memory)")
    List<MediaFile> findThumbnailsByMemoryIds(@Param("memoryIds") List<Long> memoryIds);

    @Query("SELECT mf.fileKey FROM MediaFile mf WHERE mf.memory.user.userId = :userId")
    List<String> findFileKeysByUserId(@Param("userId") Long userId);

    @Query("SELECT mf.fileKey FROM MediaFile mf WHERE mf.memory.map.mapId = :mapId")
    List<String> findFileKeysByMapId(@Param("mapId") Long mapId);

    @Query("SELECT mf FROM MediaFile mf WHERE mf.mediaFileId IN :ids AND mf.memory.memoryId = :memoryId")
    List<MediaFile> findAllByIdsAndMemoryId(@Param("ids") List<Long> ids, @Param("memoryId") Long memoryId);

    @Modifying
    @Query("DELETE FROM MediaFile mf WHERE mf.memory.user.userId = :userId")
    void deleteAllByUserId(@Param("userId") Long userId);

    @Modifying
    @Query("DELETE FROM MediaFile mf WHERE mf.memory.map.mapId = :mapId")
    void deleteAllByMapId(@Param("mapId") Long mapId);
}
