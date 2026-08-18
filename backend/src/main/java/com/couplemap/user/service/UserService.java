package com.couplemap.user.service;

import com.couplemap.user.dto.ProfileImageRequestDto;
import com.couplemap.user.dto.ProfileImageResponseDto;
import com.couplemap.user.dto.NicknameResponseDto;
import com.couplemap.user.dto.UserInfoResponseDto;

public interface UserService {
    ProfileImageResponseDto updateProfileImage(Long userId, ProfileImageRequestDto request);
    void deleteProfileImage(Long userId);
    NicknameResponseDto setNickname(Long userId, String nickname);
    UserInfoResponseDto getUserInfo(Long userId);
    void deleteAccount(Long userId);
}
