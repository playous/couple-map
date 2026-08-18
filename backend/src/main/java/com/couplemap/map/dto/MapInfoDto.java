package com.couplemap.map.dto;

import com.couplemap.map.domain.MapMember;
import com.couplemap.map.domain.MapMemberRole;
import lombok.Getter;

import java.time.LocalDateTime;
import java.util.function.Function;

@Getter
public class MapInfoDto {
    private final Long mapId;
    private final String mapName;
    private final String description;
    private final String backgroundUrl;
    private final MapMemberRole myRole;
    private long memberCount;
    private final String category;
    private final LocalDateTime createdAt;

    public MapInfoDto(Long mapId, String mapName, String description, String backgroundUrl, MapMemberRole myRole, long memberCount, String category, LocalDateTime createdAt) {
        this.mapId = mapId;
        this.mapName = mapName;
        this.description = description;
        this.backgroundUrl = backgroundUrl;
        this.myRole = myRole;
        this.memberCount = memberCount;
        this.category = category;
        this.createdAt = createdAt;
    }

    public static MapInfoDto from(MapMember mapMember, long memberCount, Function<String, String> urlOf) {
        return new MapInfoDto(
                mapMember.getMap().getMapId(),
                mapMember.getMap().getMapName(),
                mapMember.getMap().getDescription(),
                urlOf.apply(mapMember.getMap().getBackgroundKey()),
                mapMember.getMapMemberRole(),
                memberCount,
                mapMember.getMap().getCategory(),
                mapMember.getMap().getCreatedAt()
        );
    }
}
