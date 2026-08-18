package com.couplemap.map.repository;

import com.couplemap.map.domain.Map;
import com.couplemap.map.domain.MapMember;
import com.couplemap.map.domain.MapMemberRole;
import com.couplemap.user.domain.User;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

@Repository
public interface MapMemberRepository extends JpaRepository<MapMember, Long> {
    List<MapMember> findAllByUser(User user);

    Optional<MapMember> findByMap_MapIdAndUser_UserId(Long mapId, Long userId);

    List<MapMember> findAllByUserAndMapMemberRole(User user, MapMemberRole role);

    void deleteAllByMap(Map map);

    long countByMap_MapIdAndMapMemberRoleNot(Long mapId, MapMemberRole role);

    List<MapMember> findAllByMap_MapIdAndMapMemberRoleNot(Long mapId, MapMemberRole role);

    @Query("SELECT COUNT(mm) > 0 FROM MapMember mm " +
            "WHERE mm.user.userId = :userId AND mm.map.mapName = :mapName " +
            "AND mm.mapMemberRole != :role")
    boolean existsByUserIdAndMapName(@Param("userId") Long userId, @Param("mapName") String mapName,
                                     @Param("role") MapMemberRole role);

    @Query("SELECT COUNT(mm) > 0 FROM MapMember mm " +
            "WHERE mm.user.userId = :userId AND mm.map.mapName = :mapName " +
            "AND mm.map.mapId != :excludeMapId AND mm.mapMemberRole != :role")
    boolean existsByUserIdAndMapNameExcludingMapId(@Param("userId") Long userId,
                                                     @Param("mapName") String mapName,
                                                     @Param("excludeMapId") Long excludeMapId,
                                                     @Param("role") MapMemberRole role);

    @Query("SELECT mm.map FROM MapMember mm WHERE mm.user.userId = :userId AND mm.mapMemberRole = :role")
    List<Map> findOwnedMapsByUserId(@Param("userId") Long userId, @Param("role") MapMemberRole role);

    @Query("SELECT mm FROM MapMember mm JOIN FETCH mm.map WHERE mm.user = :user")
    List<MapMember> findAllByUserWithMap(@Param("user") User user);

    @Query("SELECT mm.map.mapId, COUNT(mm) FROM MapMember mm " +
            "WHERE mm.map.mapId IN :mapIds AND mm.mapMemberRole != :role " +
            "GROUP BY mm.map.mapId")
    List<Object[]> countMembersByMapIds(@Param("mapIds") List<Long> mapIds, @Param("role") MapMemberRole role);

    @Modifying
    @Query("DELETE FROM MapMember mm WHERE mm.user.userId = :userId")
    void deleteAllByUserId(@Param("userId") Long userId);

    // 탈퇴 시 inviter_id FK 잔존으로 users 삭제가 막히는 것 방지 — 행 삭제가 아니라 NULL로 끊는다
    @Modifying(flushAutomatically = true)
    @Query("UPDATE MapMember mm SET mm.inviter = NULL WHERE mm.inviter.userId = :userId")
    void clearInviterByUserId(@Param("userId") Long userId);
}
