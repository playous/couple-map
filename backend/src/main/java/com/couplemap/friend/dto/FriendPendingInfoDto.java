package com.couplemap.friend.dto;

import com.couplemap.friend.domain.Friendship;
import com.couplemap.user.domain.User;
import lombok.Builder;
import lombok.Getter;

import java.time.LocalDateTime;
import java.util.function.Function;

@Getter
@Builder
public class FriendPendingInfoDto {
    private final Long friendshipId;
    private final String nickname;
    private final String imageUrl;
    private final LocalDateTime createdAt;

    public static  FriendPendingInfoDto from(Friendship friendship, Function<String, String> urlOf) {
        User user = friendship.getRequester();
        return FriendPendingInfoDto.builder()
                .friendshipId(friendship.getFriendshipId())
                .nickname(user.getNickname())
                .imageUrl(urlOf.apply(user.getProfileImageKey()))
                .createdAt(friendship.getCreatedAt())
                .build();
    }
}
