package com.couplemap.memory.repository;

import com.couplemap.map.domain.MapMemberRole;
import com.couplemap.memory.domain.Memory;
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
    List<Memory> findAllByMap_MapId(Long mapId);

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
