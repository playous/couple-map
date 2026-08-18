package com.couplemap.map.dto;

import com.couplemap.map.domain.MapMember;
import lombok.Getter;

import java.time.LocalDateTime;

@Getter
public class MapInvitationDto {
    private final Long mapMemberId;
    private final String mapName;
    private final String inviterNickname;
    private final LocalDateTime createdAt;

    public MapInvitationDto(Long mapMemberId, String mapName, String inviterNickname, LocalDateTime createdAt) {
        this.mapMemberId = mapMemberId;
        this.mapName = mapName;
        this.inviterNickname = inviterNickname;
        this.createdAt = createdAt;
    }

    private static final String UNKNOWN_INVITER = "알 수 없음";

    public static MapInvitationDto from(MapMember mapMember) {
        return new MapInvitationDto(
                mapMember.getMapMemberId(),
                mapMember.getMap().getMapName(),
                resolveInviterNickname(mapMember),
                mapMember.getCreatedAt()
        );
    }

    // 초대자 탈퇴, 닉네임 미설정 시 null — 클라이언트가 non-null로 캐스트하므로 서버에서 막는다
    private static String resolveInviterNickname(MapMember mapMember) {
        if (mapMember.getInviter() == null) {
            return UNKNOWN_INVITER;
        }
        String nickname = mapMember.getInviter().getNickname();
        return (nickname == null || nickname.isBlank()) ? UNKNOWN_INVITER : nickname;
    }
}
