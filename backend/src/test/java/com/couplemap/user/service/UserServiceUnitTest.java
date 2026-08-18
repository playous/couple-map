package com.couplemap.user.service;

import com.couplemap.friend.repository.FriendshipRepository;
import com.couplemap.global.exception.exceptions.UserException;
import com.couplemap.global.filecleanup.FileCleanupService;
import com.couplemap.global.s3.S3Service;
import com.couplemap.global.upload.ImageUploadService;
import com.couplemap.jwt.repository.RefreshTokenRepository;
import com.couplemap.map.domain.Map;
import com.couplemap.map.domain.MapMemberRole;
import com.couplemap.map.repository.MapMemberRepository;
import com.couplemap.map.repository.MapRepository;
import com.couplemap.mediafile.repository.MediaFileRepository;
import com.couplemap.memory.repository.MemoryRepository;
import com.couplemap.user.domain.User;
import com.couplemap.user.domain.UserRole;
import com.couplemap.user.dto.NicknameResponseDto;
import com.couplemap.user.dto.ProfileImageRequestDto;
import com.couplemap.user.dto.ProfileImageResponseDto;
import com.couplemap.user.dto.UserInfoResponseDto;
import com.couplemap.user.repository.UserRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.List;
import java.util.Optional;

import static com.couplemap.global.exception.code.UserErrorCode.DUPLICATE_NICKNAME;
import static com.couplemap.global.exception.code.UserErrorCode.USER_NOT_FOUND;
import static com.couplemap.map.domain.MapMemberRole.EDITOR;
import static com.couplemap.map.domain.MapMemberRole.OWNER;
import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
@DisplayName("UserServiceImpl 단위 테스트")
class UserServiceUnitTest {

    @Mock private UserRepository userRepository;
    @Mock private MemoryRepository memoryRepository;
    @Mock private FriendshipRepository friendshipRepository;
    @Mock private MapMemberRepository mapMemberRepository;
    @Mock private MapRepository mapRepository;
    @Mock private RefreshTokenRepository refreshTokenRepository;
    @Mock private S3Service s3Service;
    @Mock private FileCleanupService fileCleanupService;
    @Mock private MediaFileRepository mediaFileRepository;
    @Mock private ImageUploadService imageUploadService;

    @InjectMocks
    private UserServiceImpl userService;

    private User testUser;
    private User otherUser;

    @BeforeEach
    void setUp() {
        testUser = User.builder()
                .loginType("KAKAO").providerId("P1").email("test@test.com")
                .name("테스트").role(UserRole.USER).friendCode("CODE1")
                .build();
        ReflectionTestUtils.setField(testUser, "userId", 1L);

        otherUser = User.builder()
                .loginType("KAKAO").providerId("P2").email("other@test.com")
                .name("다른유저").role(UserRole.USER).friendCode("CODE2")
                .build();
        ReflectionTestUtils.setField(otherUser, "userId", 2L);
    }

    // ==================== updateProfileImage ====================

    @Test
    @DisplayName("프로필 이미지 등록 성공 - 기존 이미지 없음")
    void updateProfileImage_Success_NoExisting() {
        ProfileImageRequestDto request = new ProfileImageRequestDto("upload-1", "profile/new.jpg");

        when(userRepository.findById(1L)).thenReturn(Optional.of(testUser));
        when(imageUploadService.consume("upload-1", "profile/new.jpg", 1L)).thenReturn("profile/new.jpg");
        when(s3Service.getFileUrl("profile/new.jpg")).thenReturn("https://s3/new.jpg?X-Amz-Signature=x");

        ProfileImageResponseDto result = userService.updateProfileImage(1L, request);

        assertThat(result.getImageUrl()).contains("X-Amz-Signature");
        verify(fileCleanupService, never()).scheduleDelete(any());
        assertThat(testUser.getProfileImageKey()).isEqualTo("profile/new.jpg");
    }

    @Test
    @DisplayName("프로필 이미지 등록 성공 - 기존 이미지 삭제 예약")
    void updateProfileImage_Success_WithExisting() {
        ReflectionTestUtils.setField(testUser, "profileImageKey", "profile/old.jpg");

        ProfileImageRequestDto request = new ProfileImageRequestDto("upload-1", "profile/new.jpg");

        when(userRepository.findById(1L)).thenReturn(Optional.of(testUser));
        when(imageUploadService.consume("upload-1", "profile/new.jpg", 1L)).thenReturn("profile/new.jpg");

        userService.updateProfileImage(1L, request);

        verify(fileCleanupService).scheduleDelete("profile/old.jpg");
    }

    @Test
    @DisplayName("프로필 이미지 등록 실패 - 유저 없음")
    void updateProfileImage_UserNotFound() {
        ProfileImageRequestDto request = new ProfileImageRequestDto("upload-1", "profile/new.jpg");
        when(userRepository.findById(99L)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> userService.updateProfileImage(99L, request))
                .isInstanceOf(UserException.class)
                .hasMessage(USER_NOT_FOUND.getMessage());
    }

    // ==================== deleteProfileImage ====================

    @Test
    @DisplayName("프로필 이미지 삭제 성공")
    void deleteProfileImage_Success() {
        ReflectionTestUtils.setField(testUser, "profileImageKey", "profile/old.jpg");
        when(userRepository.findById(1L)).thenReturn(Optional.of(testUser));

        userService.deleteProfileImage(1L);

        verify(fileCleanupService).scheduleDelete("profile/old.jpg");
        assertThat(testUser.getProfileImageKey()).isNull();
    }

    @Test
    @DisplayName("프로필 이미지 삭제 - 이미지 없으면 scheduleDelete 호출 안 함")
    void deleteProfileImage_NoImage() {
        when(userRepository.findById(1L)).thenReturn(Optional.of(testUser));

        userService.deleteProfileImage(1L);

        verify(fileCleanupService, never()).scheduleDelete(any());
    }

    // ==================== setNickname ====================

    @Test
    @DisplayName("닉네임 설정 성공")
    void setNickname_Success() {
        when(userRepository.findById(1L)).thenReturn(Optional.of(testUser));
        when(userRepository.findByNickname("새닉네임")).thenReturn(Optional.empty());

        NicknameResponseDto result = userService.setNickname(1L, "새닉네임");

        assertThat(result.getNickname()).isEqualTo("새닉네임");
        assertThat(testUser.getNickname()).isEqualTo("새닉네임");
    }

    @Test
    @DisplayName("닉네임 설정 성공 - 자기 자신의 닉네임 유지")
    void setNickname_Success_SameUser() {
        ReflectionTestUtils.setField(testUser, "nickname", "기존닉네임");
        when(userRepository.findById(1L)).thenReturn(Optional.of(testUser));
        when(userRepository.findByNickname("기존닉네임")).thenReturn(Optional.of(testUser));

        NicknameResponseDto result = userService.setNickname(1L, "기존닉네임");

        assertThat(result.getNickname()).isEqualTo("기존닉네임");
    }

    @Test
    @DisplayName("닉네임 설정 실패 - 중복")
    void setNickname_Duplicate() {
        when(userRepository.findById(1L)).thenReturn(Optional.of(testUser));
        when(userRepository.findByNickname("중복닉네임")).thenReturn(Optional.of(otherUser));

        assertThatThrownBy(() -> userService.setNickname(1L, "중복닉네임"))
                .isInstanceOf(UserException.class)
                .hasMessage(DUPLICATE_NICKNAME.getMessage());
    }

    // ==================== getUserInfo ====================

    @Test
    @DisplayName("사용자 정보 조회 성공 - memoryCount 포함")
    void getUserInfo_Success() {
        when(userRepository.findById(1L)).thenReturn(Optional.of(testUser));
        when(memoryRepository.countByUserMaps(1L, List.of(OWNER, EDITOR))).thenReturn(5L);

        UserInfoResponseDto result = userService.getUserInfo(1L);

        assertThat(result.getUserId()).isEqualTo(1L);
        assertThat(result.getEmail()).isEqualTo("test@test.com");
        assertThat(result.getMemoryCount()).isEqualTo(5L);
    }

    @Test
    @DisplayName("사용자 정보 조회 실패 - 유저 없음")
    void getUserInfo_UserNotFound() {
        when(userRepository.findById(99L)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> userService.getUserInfo(99L))
                .isInstanceOf(UserException.class)
                .hasMessage(USER_NOT_FOUND.getMessage());
    }

    // ==================== deleteAccount ====================

    @Test
    @DisplayName("회원 탈퇴 성공 - 전체 삭제 흐름 검증")
    void deleteAccount_Success() {
        Map ownedMap = Map.from("내 지도", "설명", "Solo");
        ReflectionTestUtils.setField(ownedMap, "mapId", 10L);
        ReflectionTestUtils.setField(ownedMap, "backgroundKey", "bg/key");
        ReflectionTestUtils.setField(testUser, "profileImageKey", "profile/key");

        when(userRepository.findById(1L)).thenReturn(Optional.of(testUser));
        when(mediaFileRepository.findFileKeysByUserId(1L)).thenReturn(List.of("media/key1"));
        when(mapMemberRepository.findOwnedMapsByUserId(1L, OWNER)).thenReturn(List.of(ownedMap));
        when(mediaFileRepository.findFileKeysByMapId(10L)).thenReturn(List.of("media/key2"));

        userService.deleteAccount(1L);

        // DB 삭제 순서 검증
        verify(mediaFileRepository).deleteAllByUserId(1L);
        verify(memoryRepository).deleteAllByUser_UserId(1L);
        verify(mediaFileRepository).deleteAllByMapId(10L);
        verify(memoryRepository).deleteAllByMap_MapId(10L);
        verify(mapMemberRepository).deleteAllByMap(ownedMap);
        verify(mapRepository).delete(ownedMap);
        verify(mapMemberRepository).deleteAllByUserId(1L);
        verify(friendshipRepository).deleteAllByUserId(1L);
        verify(refreshTokenRepository).deleteById("1");

        // S3 삭제 예약: media/key1, media/key2, bg/key, profile/key
        verify(fileCleanupService).scheduleDeleteAll(argThat(keys ->
                keys.size() == 4
                        && keys.contains("media/key1")
                        && keys.contains("media/key2")
                        && keys.contains("bg/key")
                        && keys.contains("profile/key")
        ));

        verify(userRepository).delete(testUser);
    }

    @Test
    @DisplayName("회원 탈퇴 성공 - 소유 지도 없고 프로필 이미지 없음")
    void deleteAccount_Success_NoMapsNoProfile() {
        when(userRepository.findById(1L)).thenReturn(Optional.of(testUser));
        when(mediaFileRepository.findFileKeysByUserId(1L)).thenReturn(List.of());
        when(mapMemberRepository.findOwnedMapsByUserId(1L, OWNER)).thenReturn(List.of());

        userService.deleteAccount(1L);

        verify(fileCleanupService).scheduleDeleteAll(argThat(List::isEmpty));
        verify(userRepository).delete(testUser);
    }

    @Test
    @DisplayName("회원 탈퇴 실패 - 유저 없음")
    void deleteAccount_UserNotFound() {
        when(userRepository.findById(99L)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> userService.deleteAccount(99L))
                .isInstanceOf(UserException.class)
                .hasMessage(USER_NOT_FOUND.getMessage());
    }
}
