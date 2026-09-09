package com.couplemap.map.dto;

import com.couplemap.map.domain.MapMember;
import com.couplemap.map.domain.MapMemberRole;
import lombok.Getter;
import lombok.RequiredArgsConstructor;

import java.util.function.Function;

@Getter
@RequiredArgsConstructor
public class MapMemberDto {
    private final Long userId;
    private final String nickname;
    private final String profileImageUrl;
    private final MapMemberRole role;

    public static MapMemberDto from(MapMember mapMember, Function<String, String> urlOf) {
        return new MapMemberDto(
                mapMember.getUser().getUserId(),
                mapMember.getUser().getNickname(),
                urlOf.apply(mapMember.getUser().getProfileImageKey()),
                mapMember.getMapMemberRole()
        );
    }
}
