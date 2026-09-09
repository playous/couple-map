package com.couplemap.friend.dto;

import com.couplemap.friend.domain.Friendship;
import com.couplemap.user.domain.User;
import lombok.AllArgsConstructor;
import lombok.Getter;

import java.util.ArrayList;
import java.util.List;
import java.util.function.Function;

@Getter
@AllArgsConstructor
public class FriendPendingListResponseDto {
    private final List<FriendPendingInfoDto> friendPendingInfoDtoList;

    public static FriendPendingListResponseDto from(List<Friendship> friendships,
                                                    Function<String, String> urlOf) {
        List<FriendPendingInfoDto> friendPendingList = new ArrayList<>();
        for (Friendship friendship : friendships) {
            friendPendingList.add(FriendPendingInfoDto.from(friendship, urlOf));
        }
        return new FriendPendingListResponseDto(friendPendingList);
    }
}
