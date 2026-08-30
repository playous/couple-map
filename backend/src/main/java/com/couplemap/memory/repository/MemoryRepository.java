package com.couplemap.memory.repository;

import com.couplemap.map.domain.MapMemberRole;
import com.couplemap.memory.domain.Memory;
import com.couplemap.memory.dto.MemoryMarkerResponseDto;
import org.springframework.data.domain.Pageable;
import org.springframework.data.domain.Slice;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.time.LocalDate;
import java.util.List;

@Repository
public interface MemoryRepository extends JpaRepository<Memory, Long> {
    // 마커는 5개 필드만 쓰므로 엔티티 대신 DTO로 바로 뽑는다. 커버링 인덱스와 함께 본문 접근 없이 동작
    @Query("SELECT new com.couplemap.memory.dto.MemoryMarkerResponseDto(" +
            "m.memoryId, m.latitude, m.longitude, m.category, m.memoryDate) " +
            "FROM Memory m WHERE m.map.mapId = :mapId")
    List<MemoryMarkerResponseDto> findMarkersByMapId(@Param("mapId") Long mapId);

    Slice<Memory> findByMap_MapId(Long mapId, Pageable pageable);

    @Query("SELECT m FROM Memory m " +
            "JOIN MapMember mm ON m.map = mm.map " +
            "WHERE mm.user.userId = :userId " +
            "AND mm.mapMemberRole IN :roles " +
            "AND m.memoryDate BETWEEN :from AND :to " +
            "ORDER BY m.memoryDate ASC")
    List<Memory> findAllByUserIdAndYear(@Param("userId") Long userId,
                                        @Param("from") LocalDate from, @Param("to") LocalDate to,
                                        @Param("roles") List<MapMemberRole> roles);

    @Query("SELECT COUNT(m) FROM Memory m " +
            "JOIN MapMember mm ON m.map = mm.map " +
            "WHERE mm.user.userId = :userId " +
            "AND mm.mapMemberRole IN :roles")
    long countByUserMaps(@Param("userId") Long userId, @Param("roles") List<MapMemberRole> roles);

    void deleteAllByUser_UserId(Long userId);

    void deleteAllByMap_MapId(Long mapId);
}
