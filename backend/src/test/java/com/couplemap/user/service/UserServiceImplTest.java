package com.couplemap.user.service;

import com.couplemap.friend.domain.Friendship;
import com.couplemap.friend.domain.FriendshipStatus;
import com.couplemap.friend.repository.FriendshipRepository;
import com.couplemap.global.exception.exceptions.S3Exception;
import com.couplemap.global.upload.ImageUploadRequestDto;
import com.couplemap.global.upload.ImageUploadResponseDto;
import com.couplemap.global.upload.ImageUploadService;
import com.couplemap.map.domain.Map;
import com.couplemap.map.domain.MapMember;
import com.couplemap.map.domain.MapMemberRole;
import com.couplemap.map.repository.MapMemberRepository;
import com.couplemap.map.repository.MapRepository;
import com.couplemap.memory.domain.Memory;
import com.couplemap.memory.repository.MemoryRepository;
import com.couplemap.user.domain.User;
import com.couplemap.user.domain.UserRole;
import com.couplemap.user.dto.ProfileImageRequestDto;
import com.couplemap.user.dto.ProfileImageResponseDto;
import com.couplemap.user.repository.UserRepository;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;

import java.math.BigDecimal;
import java.time.LocalDate;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

@SpringBootTest
class UserServiceImplTest {

    @Autowired private UserService userService;
    @Autowired private UserRepository userRepository;
    @Autowired private MapRepository mapRepository;
    @Autowired private MapMemberRepository mapMemberRepository;
    @Autowired private MemoryRepository memoryRepository;
    @Autowired private FriendshipRepository friendshipRepository;
    @Autowired private ImageUploadService imageUploadService;

    private User testUser;

    @BeforeEach
    void setUp() {
        testUser = userRepository.save(User.builder()
                .email("test@example.com").name("테스트유저").friendCode("TEST1234")
                .providerId("TEST12341").loginType("KAKAO").role(UserRole.USER)
                .build());
    }

    @AfterEach
    void cleanup() {
        if (testUser != null) {
            try { userRepository.delete(testUser); } catch (Exception ignored) {}
        }
    }

    @Test
    @DisplayName("통합: 발급 -> 등록 시 file_key만 저장하고 URL은 서명해서 내려준다")
    void updateProfileImage_StoresKeyOnly() {
        ImageUploadResponseDto issued = imageUploadService.issue(
                new ImageUploadRequestDto("first.png", "image/png", 1024L), testUser.getUserId());

        ProfileImageResponseDto response = userService.updateProfileImage(
                testUser.getUserId(),
                new ProfileImageRequestDto(issued.getUploadId(), issued.getFileKey()));

        assertThat(response.getImageUrl()).contains("X-Amz-Signature");

        User updatedUser = userRepository.findById(testUser.getUserId()).orElseThrow();
        assertThat(updatedUser.getProfileImageKey()).contains("profile/");
    }

    @Test
    @DisplayName("통합: 프로필 이미지 교체 - 키가 바뀐다")
    void updateProfileImage_Replace() {
        ImageUploadResponseDto first = imageUploadService.issue(
                new ImageUploadRequestDto("first.png", "image/png", 1024L), testUser.getUserId());
        userService.updateProfileImage(testUser.getUserId(),
                new ProfileImageRequestDto(first.getUploadId(), first.getFileKey()));

        String firstKey = userRepository.findById(testUser.getUserId()).orElseThrow().getProfileImageKey();

        ImageUploadResponseDto second = imageUploadService.issue(
                new ImageUploadRequestDto("second.png", "image/png", 1024L), testUser.getUserId());
        userService.updateProfileImage(testUser.getUserId(),
                new ProfileImageRequestDto(second.getUploadId(), second.getFileKey()));

        User updatedUser = userRepository.findById(testUser.getUserId()).orElseThrow();
        assertThat(updatedUser.getProfileImageKey()).isNotEqualTo(firstKey);
    }

    @Test
    @DisplayName("통합: 발급하지 않은 fileKey는 거부한다")
    void updateProfileImage_RejectsForeignKey() {
        ImageUploadResponseDto issued = imageUploadService.issue(
                new ImageUploadRequestDto("first.png", "image/png", 1024L), testUser.getUserId());

        assertThatThrownBy(() -> userService.updateProfileImage(
                testUser.getUserId(),
                new ProfileImageRequestDto(issued.getUploadId(), "profile/someone-else.png")))
                .isInstanceOf(S3Exception.class);
    }

    @Test
    @DisplayName("통합: 회원 탈퇴 - 실제 DB FK 순서 삭제")
    void deleteAccount_RealDB() {
        User friendUser = userRepository.save(User.builder()
                .email("friend@example.com").name("친구유저").friendCode("FRIEND01")
                .providerId("FRIEND01").loginType("KAKAO").role(UserRole.USER)
                .build());

        Map ownedMap = mapRepository.save(Map.from("우리의 지도", "설명", "COUPLE"));
        mapMemberRepository.save(MapMember.from(ownedMap, testUser, MapMemberRole.OWNER));
        mapMemberRepository.save(MapMember.from(ownedMap, friendUser, testUser, MapMemberRole.EDITOR));

        memoryRepository.save(Memory.builder()
                .map(ownedMap).user(testUser).title("첫 데이트").placeName("카페")
                .address("서울시 강남구").memoryDate(LocalDate.of(2025, 1, 1))
                .latitude(new BigDecimal("37.12345678")).longitude(new BigDecimal("127.12345678"))
                .category("CAFE").build());

        friendshipRepository.save(Friendship.createRequest(testUser, friendUser));

        Long userId = testUser.getUserId();
        Long mapId = ownedMap.getMapId();

        userService.deleteAccount(userId);

        assertThat(userRepository.findById(userId)).isEmpty();
        assertThat(mapRepository.findById(mapId)).isEmpty();
        assertThat(memoryRepository.findAllByMap_MapId(mapId)).isEmpty();
        assertThat(friendshipRepository.findFriendsWhereRequester(userId, FriendshipStatus.PENDING)).isEmpty();

        testUser = null;
        userRepository.delete(friendUser);
    }
}
