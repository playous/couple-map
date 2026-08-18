package com.couplemap.user.controller;

import com.couplemap.global.response.ApiResponse;
import com.couplemap.user.dto.ProfileImageRequestDto;
import com.couplemap.user.dto.ProfileImageResponseDto;
import com.couplemap.user.dto.NicknameRequestDto;
import com.couplemap.user.dto.NicknameResponseDto;
import com.couplemap.user.dto.UserInfoResponseDto;
import com.couplemap.user.service.UserService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.*;


@Tag(name = "User", description = "사용자 관리 API")
@RestController
@RequestMapping("/api/users")
@RequiredArgsConstructor
public class UserController {

    private final UserService userService;

    @Operation(summary = "프로필 이미지 등록", description = "/api/uploads/image로 발급받아 S3에 올린 뒤 호출합니다.")
    @PostMapping("/profile-image")
    public ResponseEntity<ApiResponse<ProfileImageResponseDto>> uploadProfileImage(
            @Valid @RequestBody ProfileImageRequestDto request,
            @AuthenticationPrincipal(expression = "userId") Long userId) {

        ProfileImageResponseDto response = userService.updateProfileImage(userId, request);

        return ResponseEntity.ok(ApiResponse.success(response, "프로필 사진 등록이 완료되었습니다."));
    }

    @Operation(summary = "프로필 이미지 삭제")
    @DeleteMapping("/profile-image")
    public ResponseEntity<ApiResponse<Void>> deleteProfileImage(
            @AuthenticationPrincipal(expression = "userId") Long userId) {
        userService.deleteProfileImage(userId);
        return ResponseEntity.ok(ApiResponse.success("프로필 사진이 삭제되었습니다."));
    }

    @Operation(summary = "닉네임 설정", description = "회원가입 후 사용자의 닉네임을 설정합니다. (최초 1회 또는 변경 시)")
    @PostMapping("/nickname")
    public ResponseEntity<ApiResponse<NicknameResponseDto>> setNickname(
            @Valid @RequestBody NicknameRequestDto request,
            @AuthenticationPrincipal(expression = "userId") Long userId) {
        
        NicknameResponseDto response = userService.setNickname(userId, request.getNickname());
        return ResponseEntity.ok(ApiResponse.success(response, "닉네임이 설정되었습니다."));
    }

    @Operation(summary = "내 정보 조회")
    @GetMapping("/me")
    public ResponseEntity<ApiResponse<UserInfoResponseDto>> getMyInfo(
            @AuthenticationPrincipal(expression = "userId") Long userId) {

        UserInfoResponseDto response = userService.getUserInfo(userId);
        return ResponseEntity.ok(ApiResponse.success(response, "내 정보 조회 성공"));
    }

    @Operation(summary = "회원 탈퇴", description = "계정 및 모든 관련 데이터를 삭제합니다")
    @DeleteMapping("/me")
    public ResponseEntity<ApiResponse<Void>> deleteAccount(
            @AuthenticationPrincipal(expression = "userId") Long userId) {
        userService.deleteAccount(userId);
        return ResponseEntity.ok(ApiResponse.success("회원 탈퇴가 완료되었습니다."));
    }
}
