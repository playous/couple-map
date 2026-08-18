package com.couplemap.user.dto;

import com.couplemap.user.domain.User;
import lombok.Builder;
import lombok.Getter;

import java.time.LocalDateTime;
import java.util.function.Function;

@Getter
@Builder
public class UserInfoResponseDto {

    private Long userId;

    private String email;

    private String name;

    private String nickname;

    private String profileImageUrl;

    private String friendCode;

    private LocalDateTime createdAt;

    private long memoryCount;

    public static UserInfoResponseDto from(User user, long memoryCount, Function<String, String> urlOf) {
        return UserInfoResponseDto.builder()
                .userId(user.getUserId())
                .email(user.getEmail())
                .name(user.getName())
                .nickname(user.getNickname())
                .profileImageUrl(urlOf.apply(user.getProfileImageKey()))
                .friendCode(user.getFriendCode())
                .createdAt(user.getCreatedAt())
                .memoryCount(memoryCount)
                .build();
    }
}
