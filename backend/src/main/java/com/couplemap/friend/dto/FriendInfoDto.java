package com.couplemap.friend.dto;

import com.couplemap.user.domain.User;
import lombok.Builder;
import lombok.Getter;

import java.util.function.Function;

@Getter
@Builder
public class FriendInfoDto {

    private final Long id;
    private final String nickname;
    private final String friendCode;
    private final String imageUrl;

    public static FriendInfoDto from(User user, Function<String, String> urlOf) {
        return FriendInfoDto.builder()
                .id(user.getUserId())
                .nickname(user.getNickname())
                .friendCode(user.getFriendCode())
                .imageUrl(urlOf.apply(user.getProfileImageKey()))
                .build();
    }
}
