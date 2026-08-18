package com.couplemap.map.service;

import com.couplemap.friend.domain.FriendshipStatus;
import com.couplemap.friend.repository.FriendshipRepository;
import com.couplemap.global.exception.exceptions.FriendException;
import com.couplemap.global.exception.exceptions.MapException;
import com.couplemap.global.exception.exceptions.UserException;
import com.couplemap.global.filecleanup.FileCleanupService;
import com.couplemap.global.s3.S3Service;
import com.couplemap.global.upload.ImageUploadService;
import com.couplemap.map.domain.Map;
import com.couplemap.map.domain.MapMember;
import com.couplemap.map.domain.MapMemberRole;
import com.couplemap.map.dto.*;
import com.couplemap.map.repository.MapMemberRepository;
import com.couplemap.map.repository.MapRepository;
import com.couplemap.mediafile.repository.MediaFileRepository;
import com.couplemap.memory.repository.MemoryRepository;
import com.couplemap.user.domain.User;
import com.couplemap.user.domain.UserRole;
import com.couplemap.user.repository.UserRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.Arrays;
import java.util.Collections;
import java.util.List;
import java.util.Optional;

import static com.couplemap.global.exception.code.FriendErrorCode.INVALID_FRIENDSHIP_ID;
import static com.couplemap.global.exception.code.MapErrorCode.*;
import static com.couplemap.global.exception.code.UserErrorCode.USER_NOT_FOUND;
import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
@DisplayName("MapServiceImpl 테스트")
public class MapServiceImplTest {

    @Mock
    private MapRepository mapRepository;

    @Mock
    private MapMemberRepository mapMemberRepository;

    @Mock
    private UserRepository userRepository;

    @Mock
    private FriendshipRepository friendshipRepository;

    @Mock
    private S3Service s3Service;

    @Mock
    private ImageUploadService imageUploadService;

    @Mock
    private FileCleanupService fileCleanupService;

    @Mock
    private MemoryRepository memoryRepository;

    @Mock
    private MediaFileRepository mediaFileRepository;

    @InjectMocks
    private MapServiceImpl mapService;

    private User testUser;
    private User friendUser;
    private Map testMap;
    private MapMember testMapMember;

    @BeforeEach
    void setUp() {
        testUser = User.builder()
                .loginType("GOOGLE")
                .providerId("123456")
                .email("test@example.com")
                .name("Test User")
                .role(UserRole.USER)
                .friendCode("FRIEND123")
                .build();
        ReflectionTestUtils.setField(testUser, "userId", 1L);

        friendUser = User.builder()
                .loginType("GOOGLE")
                .providerId("789012")
                .email("friend@example.com")
                .name("Friend User")
                .role(UserRole.USER)
                .friendCode("FRIEND456")
                .build();
        ReflectionTestUtils.setField(friendUser, "userId", 2L);

        testMap = Map.from("Test Map", "Test Description", "Solo");
        ReflectionTestUtils.setField(testMap, "mapId", 1L);

        testMapMember = MapMember.from(testMap, testUser, MapMemberRole.OWNER);
    }

    @Test
    @DisplayName("지도 생성 성공")
    void createMap_Success() {
        // given
        CreateMapRequestDto request = new CreateMapRequestDto("New Map", "Description", "Solo", null, null);
        Long userId = 1L;

        when(userRepository.findById(userId)).thenReturn(Optional.of(testUser));
        when(mapMemberRepository.existsByUserIdAndMapName(userId, request.getMapName(), MapMemberRole.PENDING)).thenReturn(false);
        when(mapRepository.save(any(Map.class))).thenAnswer(invocation -> invocation.getArgument(0));

        // when
        Long mapId = mapService.createMap(request, userId);

        // then
        verify(userRepository).findById(userId);
        verify(mapMemberRepository).existsByUserIdAndMapName(userId, request.getMapName(), MapMemberRole.PENDING);
        verify(mapRepository).save(any(Map.class));
        verify(mapMemberRepository).save(any(MapMember.class));
    }

    @Test
    @DisplayName("지도 생성 실패 - 지도 이름 중복")
    void createMap_MapNameDuplicated() {
        // given
        CreateMapRequestDto request = new CreateMapRequestDto("Duplicate Map", "Description", "Solo", null, null);
        Long userId = 1L;

        when(userRepository.findById(userId)).thenReturn(Optional.of(testUser));
        when(mapMemberRepository.existsByUserIdAndMapName(userId, request.getMapName(), MapMemberRole.PENDING)).thenReturn(true);

        // when & then
        assertThatThrownBy(() -> mapService.createMap(request, userId))
                .isInstanceOf(MapException.class)
                .hasMessage(MAP_NAME_DUPLICATED.getMessage());
    }

    @Test
    @DisplayName("지도 삭제 성공")
    void deleteMap_Success() {
        // given
        Long mapId = 1L;
        Long userId = 1L;

        when(mapMemberRepository.findByMap_MapIdAndUser_UserId(mapId, userId)).thenReturn(Optional.of(testMapMember));
        when(mediaFileRepository.findFileKeysByMapId(mapId)).thenReturn(List.of());

        // when
        mapService.deleteMap(mapId, userId);

        // then
        verify(mapMemberRepository).findByMap_MapIdAndUser_UserId(mapId, userId);
        verify(mediaFileRepository).findFileKeysByMapId(mapId);
        verify(mapMemberRepository).deleteAllByMap(testMap);
        verify(mapRepository).delete(testMap);
    }

    @Test
    @DisplayName("지도 삭제 실패 - 삭제 권한 없음")
    void deleteMap_NoDeletePermission() {
        // given
        Long mapId = 1L;
        Long userId = 1L;
        MapMember editorMember = MapMember.from(testMap, testUser, MapMemberRole.EDITOR);

        when(mapMemberRepository.findByMap_MapIdAndUser_UserId(mapId, userId)).thenReturn(Optional.of(editorMember));

        // when & then
        assertThatThrownBy(() -> mapService.deleteMap(mapId, userId))
                .isInstanceOf(MapException.class)
                .hasMessage(NO_DELETE_PERMISSION.getMessage());
    }

    @Test
    @DisplayName("지도 수정 성공")
    void updateMap_Success() {
        // given
        Long mapId = 1L;
        Long userId = 1L;
        UpdateMapRequestDto request = new UpdateMapRequestDto("Updated Map", "Updated Description", "Solo", null, null);

        when(mapRepository.findById(mapId)).thenReturn(Optional.of(testMap));
        when(mapMemberRepository.findByMap_MapIdAndUser_UserId(mapId, userId)).thenReturn(Optional.of(testMapMember));
        when(mapMemberRepository.existsByUserIdAndMapNameExcludingMapId(userId, request.getMapName(), mapId, MapMemberRole.PENDING)).thenReturn(false);

        // when
        mapService.updateMap(mapId, request, userId);

        // then
        verify(mapRepository).findById(mapId);
        verify(mapMemberRepository).findByMap_MapIdAndUser_UserId(mapId, userId);
        verify(mapMemberRepository).existsByUserIdAndMapNameExcludingMapId(userId, request.getMapName(), mapId, MapMemberRole.PENDING);
        assertThat(testMap.getMapName()).isEqualTo("Updated Map");
        assertThat(testMap.getDescription()).isEqualTo("Updated Description");
    }

    @Test
    @DisplayName("지도 수정 실패 - 수정 권한 없음")
    void updateMap_NoUpdatePermission() {
        // given
        Long mapId = 1L;
        Long userId = 1L;
        UpdateMapRequestDto request = new UpdateMapRequestDto("Updated Map", "Updated Description", "Solo", null, null);
        MapMember editorMember = MapMember.from(testMap, testUser, MapMemberRole.EDITOR);

        when(mapRepository.findById(mapId)).thenReturn(Optional.of(testMap));
        when(mapMemberRepository.findByMap_MapIdAndUser_UserId(mapId, userId)).thenReturn(Optional.of(editorMember));

        // when & then
        assertThatThrownBy(() -> mapService.updateMap(mapId, request, userId))
                .isInstanceOf(MapException.class)
                .hasMessage(NO_UPDATE_PERMISSION.getMessage());
    }

    @Test
    @DisplayName("지도 수정 실패 - 지도 이름 중복")
    void updateMap_MapNameDuplicated() {
        // given
        Long mapId = 1L;
        Long userId = 1L;
        UpdateMapRequestDto request = new UpdateMapRequestDto("Duplicate Map", "Updated Description", "Solo", null, null);

        when(mapRepository.findById(mapId)).thenReturn(Optional.of(testMap));
        when(mapMemberRepository.findByMap_MapIdAndUser_UserId(mapId, userId)).thenReturn(Optional.of(testMapMember));
        when(mapMemberRepository.existsByUserIdAndMapNameExcludingMapId(userId, request.getMapName(), mapId, MapMemberRole.PENDING)).thenReturn(true);

        // when & then
        assertThatThrownBy(() -> mapService.updateMap(mapId, request, userId))
                .isInstanceOf(MapException.class)
                .hasMessage(MAP_NAME_DUPLICATED.getMessage());
    }

    @Test
    @DisplayName("지도 목록 조회 성공 - PENDING 제외")
    void getMapList_ExcludePending() {
        // given
        Long userId = 1L;
        Map map1 = Map.from("Map 1", "Description 1", "Friends");
        ReflectionTestUtils.setField(map1, "mapId", 10L);
        Map map2 = Map.from("Map 2", "Description 2", "Couple");
        ReflectionTestUtils.setField(map2, "mapId", 20L);
        MapMember ownerMember = MapMember.from(map1, testUser, MapMemberRole.OWNER);
        MapMember pendingMember = MapMember.from(map2, testUser, testUser, MapMemberRole.PENDING);

        when(userRepository.findById(userId)).thenReturn(Optional.of(testUser));
        when(mapMemberRepository.findAllByUserWithMap(testUser)).thenReturn(Arrays.asList(ownerMember, pendingMember));
        List<Object[]> countResult = Collections.singletonList(new Object[]{10L, 1L});
        when(mapMemberRepository.countMembersByMapIds(List.of(10L), MapMemberRole.PENDING)).thenReturn(countResult);

        // when
        List<MapInfoDto> result = mapService.getMapList(userId);

        // then
        assertThat(result).hasSize(1);
        assertThat(result.get(0).getMapName()).isEqualTo("Map 1");
    }

    @Test
    @DisplayName("친구 초대 성공 - OWNER")
    void inviteFriend_Success_Owner() {
        // given
        Long mapId = 1L;
        Long userId = 1L;
        InviteFriendRequestDto request = new InviteFriendRequestDto(2L);

        when(userRepository.findById(userId)).thenReturn(Optional.of(testUser));
        when(mapMemberRepository.findByMap_MapIdAndUser_UserId(mapId, userId)).thenReturn(Optional.of(testMapMember));
        when(userRepository.findById(request.getFriendId())).thenReturn(Optional.of(friendUser));
        when(friendshipRepository.existsFriendship(testUser, friendUser, FriendshipStatus.ACCEPTED)).thenReturn(true);
        when(mapMemberRepository.findByMap_MapIdAndUser_UserId(mapId, friendUser.getUserId())).thenReturn(Optional.empty());

        // when
        mapService.inviteFriend(mapId, request, userId);

        // then
        verify(mapMemberRepository).save(any(MapMember.class));
    }

    @Test
    @DisplayName("친구 초대 실패 - 초대 권한 없음")
    void inviteFriend_NoInvitePermission() {
        // given
        Long mapId = 1L;
        Long userId = 1L;
        InviteFriendRequestDto request = new InviteFriendRequestDto(2L);
        MapMember viewerMember = MapMember.from(testMap, testUser, MapMemberRole.VIEWER);

        when(userRepository.findById(userId)).thenReturn(Optional.of(testUser));
        when(mapMemberRepository.findByMap_MapIdAndUser_UserId(mapId, userId)).thenReturn(Optional.of(viewerMember));

        // when & then
        assertThatThrownBy(() -> mapService.inviteFriend(mapId, request, userId))
                .isInstanceOf(MapException.class)
                .hasMessage(NO_INVITE_PERMISSION.getMessage());
    }

    @Test
    @DisplayName("친구 초대 실패 - 이미 지도 멤버")
    void inviteFriend_AlreadyMapMember() {
        // given
        Long mapId = 1L;
        Long userId = 1L;
        InviteFriendRequestDto request = new InviteFriendRequestDto(2L);
        MapMember existingMember = MapMember.from(testMap, friendUser, MapMemberRole.EDITOR);

        when(userRepository.findById(userId)).thenReturn(Optional.of(testUser));
        when(mapMemberRepository.findByMap_MapIdAndUser_UserId(mapId, userId)).thenReturn(Optional.of(testMapMember));
        when(userRepository.findById(request.getFriendId())).thenReturn(Optional.of(friendUser));
        when(friendshipRepository.existsFriendship(testUser, friendUser, FriendshipStatus.ACCEPTED)).thenReturn(true);
        when(mapMemberRepository.findByMap_MapIdAndUser_UserId(mapId, friendUser.getUserId())).thenReturn(Optional.of(existingMember));

        // when & then
        assertThatThrownBy(() -> mapService.inviteFriend(mapId, request, userId))
                .isInstanceOf(MapException.class)
                .hasMessage(ALREADY_MAP_MEMBER.getMessage());
    }

    @Test
    @DisplayName("초대 수락 성공")
    void acceptInvitation_Success() {
        // given
        Long mapMemberId = 1L;
        Long userId = 1L;
        MapMember pendingMember = MapMember.from(testMap, testUser, friendUser, MapMemberRole.PENDING);

        when(userRepository.findById(userId)).thenReturn(Optional.of(testUser));
        when(mapMemberRepository.findById(mapMemberId)).thenReturn(Optional.of(pendingMember));

        // when
        mapService.acceptInvitation(mapMemberId, userId);

        // then
        assertThat(pendingMember.getMapMemberRole()).isEqualTo(MapMemberRole.EDITOR);
    }

    @Test
    @DisplayName("초대 수락 실패 - 초대받은 사용자 아님")
    void acceptInvitation_NotInvitedUser() {
        // given
        Long mapMemberId = 1L;
        Long userId = 1L;
        MapMember pendingMember = MapMember.from(testMap, friendUser, testUser, MapMemberRole.PENDING);

        when(userRepository.findById(userId)).thenReturn(Optional.of(testUser));
        when(mapMemberRepository.findById(mapMemberId)).thenReturn(Optional.of(pendingMember));

        // when & then
        assertThatThrownBy(() -> mapService.acceptInvitation(mapMemberId, userId))
                .isInstanceOf(MapException.class)
                .hasMessage(NOT_INVITED_USER.getMessage());
    }

    @Test
    @DisplayName("초대 거절 성공")
    void rejectInvitation_Success() {
        // given
        Long mapMemberId = 1L;
        Long userId = 1L;
        MapMember pendingMember = MapMember.from(testMap, testUser, friendUser, MapMemberRole.PENDING);

        when(userRepository.findById(userId)).thenReturn(Optional.of(testUser));
        when(mapMemberRepository.findById(mapMemberId)).thenReturn(Optional.of(pendingMember));

        // when
        mapService.rejectInvitation(mapMemberId, userId);

        // then
        verify(mapMemberRepository).delete(pendingMember);
    }

    @Test
    @DisplayName("초대 거절 실패 - 초대받은 사용자 아님")
    void rejectInvitation_NotInvitedUser() {
        // given
        Long mapMemberId = 1L;
        Long userId = 1L;
        MapMember pendingMember = MapMember.from(testMap, friendUser, testUser, MapMemberRole.PENDING);

        when(userRepository.findById(userId)).thenReturn(Optional.of(testUser));
        when(mapMemberRepository.findById(mapMemberId)).thenReturn(Optional.of(pendingMember));

        // when & then
        assertThatThrownBy(() -> mapService.rejectInvitation(mapMemberId, userId))
                .isInstanceOf(MapException.class)
                .hasMessage(NOT_INVITED_USER.getMessage());
    }


    @Test
    @DisplayName("초대 목록 조회 성공")
    void getInvitationList_Success() {
        // given
        Long userId = 1L;
        Map map1 = Map.from("Map 1", "Description 1", "Friends");
        Map map2 = Map.from("Map 2", "Description 2", "Couple");
        MapMember invitation1 = MapMember.from(map1, testUser, friendUser, MapMemberRole.PENDING);
        MapMember invitation2 = MapMember.from(map2, testUser, friendUser, MapMemberRole.PENDING);

        when(userRepository.findById(userId)).thenReturn(Optional.of(testUser));
        when(mapMemberRepository.findAllByUserAndMapMemberRole(testUser, MapMemberRole.PENDING))
                .thenReturn(Arrays.asList(invitation1, invitation2));

        // when
        List<MapInvitationDto> result = mapService.getInvitationList(userId);

        // then
        assertThat(result).hasSize(2);
        assertThat(result.get(0).getMapName()).isEqualTo("Map 1");
        assertThat(result.get(1).getMapName()).isEqualTo("Map 2");
    }

    @Test
    @DisplayName("초대 목록 조회 실패 - 사용자 없음")
    void getInvitationList_UserNotFound() {
        // given
        Long userId = 1L;

        when(userRepository.findById(userId)).thenReturn(Optional.empty());

        // when & then
        assertThatThrownBy(() -> mapService.getInvitationList(userId))
                .isInstanceOf(UserException.class)
                .hasMessage(USER_NOT_FOUND.getMessage());
    }

    @Test
    @DisplayName("지도 생성 성공 - 배경 이미지 포함")
    void createMap_WithBackgroundImage_Success() {
        // given
        CreateMapRequestDto request = new CreateMapRequestDto(
                "New Map", "Description", "Solo", "upload-1", "profile/test.jpg");
        Long userId = 1L;

        when(userRepository.findById(userId)).thenReturn(Optional.of(testUser));
        when(mapMemberRepository.existsByUserIdAndMapName(userId, request.getMapName(), MapMemberRole.PENDING)).thenReturn(false);
        when(imageUploadService.consume("upload-1", "profile/test.jpg", userId)).thenReturn("profile/test.jpg");
        when(mapRepository.save(any(Map.class))).thenAnswer(invocation -> invocation.getArgument(0));

        // when
        mapService.createMap(request, userId);

        // then
        verify(imageUploadService).consume("upload-1", "profile/test.jpg", userId);
        verify(mapRepository).save(any(Map.class));
        verify(mapMemberRepository).save(any(MapMember.class));
    }

    @Test
    @DisplayName("지도 생성 성공 - 배경 이미지 없음")
    void createMap_WithoutBackgroundImage_Success() {
        // given
        CreateMapRequestDto request = new CreateMapRequestDto(
                "New Map", "Description", "Solo", null, null);
        Long userId = 1L;

        when(userRepository.findById(userId)).thenReturn(Optional.of(testUser));
        when(mapMemberRepository.existsByUserIdAndMapName(userId, request.getMapName(), MapMemberRole.PENDING)).thenReturn(false);
        when(mapRepository.save(any(Map.class))).thenAnswer(invocation -> invocation.getArgument(0));

        // when
        mapService.createMap(request, userId);

        // then
        verify(imageUploadService, never()).consume(any(), any(), any());
        verify(mapRepository).save(any(Map.class));
    }

    @Test
    @DisplayName("지도 수정 성공 - 배경 이미지 변경")
    void updateMap_WithBackgroundImage_Success() {
        // given
        Long mapId = 1L;
        Long userId = 1L;
        UpdateMapRequestDto request = new UpdateMapRequestDto(
                "Updated Map", "Updated Description", "Solo", "upload-1", "profile/new_test.jpg");

        // 기존 배경 이미지가 있는 지도 설정
        ReflectionTestUtils.setField(testMap, "backgroundKey", "old_test.jpg");

        when(mapRepository.findById(mapId)).thenReturn(Optional.of(testMap));
        when(mapMemberRepository.findByMap_MapIdAndUser_UserId(mapId, userId)).thenReturn(Optional.of(testMapMember));
        when(mapMemberRepository.existsByUserIdAndMapNameExcludingMapId(userId, request.getMapName(), mapId, MapMemberRole.PENDING)).thenReturn(false);
        when(imageUploadService.consume("upload-1", "profile/new_test.jpg", userId)).thenReturn("profile/new_test.jpg");

        // when
        mapService.updateMap(mapId, request, userId);

        // then
        verify(fileCleanupService).scheduleDelete("old_test.jpg");
        assertThat(testMap.getBackgroundKey()).isEqualTo("profile/new_test.jpg");
    }

    @Test
    @DisplayName("지도 수정 성공 - 기존 배경 이미지 없이 새 이미지 추가")
    void updateMap_AddBackgroundImage_Success() {
        // given
        Long mapId = 1L;
        Long userId = 1L;
        UpdateMapRequestDto request = new UpdateMapRequestDto(
                "Updated Map", "Updated Description", "Solo", "upload-1", "profile/new_test.jpg");

        when(mapRepository.findById(mapId)).thenReturn(Optional.of(testMap));
        when(mapMemberRepository.findByMap_MapIdAndUser_UserId(mapId, userId)).thenReturn(Optional.of(testMapMember));
        when(mapMemberRepository.existsByUserIdAndMapNameExcludingMapId(userId, request.getMapName(), mapId, MapMemberRole.PENDING)).thenReturn(false);
        when(imageUploadService.consume("upload-1", "profile/new_test.jpg", userId)).thenReturn("profile/new_test.jpg");

        // when
        mapService.updateMap(mapId, request, userId);

        // then
        verify(fileCleanupService, never()).scheduleDelete(any());
        assertThat(testMap.getBackgroundKey()).isEqualTo("profile/new_test.jpg");
    }

    @Test
    @DisplayName("지도 생성 실패 - 사용자 없음")
    void createMap_UserNotFound() {
        CreateMapRequestDto request = new CreateMapRequestDto("Map", "Desc", "Solo", null, null);

        when(userRepository.findById(99L)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> mapService.createMap(request, 99L))
                .isInstanceOf(UserException.class)
                .hasMessage(USER_NOT_FOUND.getMessage());
    }

    @Test
    @DisplayName("지도 삭제 실패 - 맵 멤버 아님")
    void deleteMap_NotMapMember() {
        when(mapMemberRepository.findByMap_MapIdAndUser_UserId(1L, 99L)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> mapService.deleteMap(1L, 99L))
                .isInstanceOf(MapException.class)
                .hasMessage(NOT_MAP_MEMBER.getMessage());
    }

    @Test
    @DisplayName("지도 삭제 성공 - 전체 삭제 흐름 검증")
    void deleteMap_Success_FullFlow() {
        Long mapId = 1L;
        Long userId = 1L;
        ReflectionTestUtils.setField(testMap, "backgroundKey", "bg/old.jpg");

        when(mapMemberRepository.findByMap_MapIdAndUser_UserId(mapId, userId)).thenReturn(Optional.of(testMapMember));
        when(mediaFileRepository.findFileKeysByMapId(mapId)).thenReturn(List.of("media/k1", "media/k2"));

        mapService.deleteMap(mapId, userId);

        verify(fileCleanupService).scheduleDeleteAll(List.of("media/k1", "media/k2"));
        verify(mediaFileRepository).deleteAllByMapId(mapId);
        verify(memoryRepository).deleteAllByMap_MapId(mapId);
        verify(fileCleanupService).scheduleDelete("bg/old.jpg");
        verify(mapMemberRepository).deleteAllByMap(testMap);
        verify(mapRepository).delete(testMap);
    }

    @Test
    @DisplayName("지도 수정 실패 - 맵 없음")
    void updateMap_MapNotFound() {
        UpdateMapRequestDto request = new UpdateMapRequestDto("Updated", "Desc", "Solo", null, null);

        when(mapRepository.findById(99L)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> mapService.updateMap(99L, request, 1L))
                .isInstanceOf(MapException.class)
                .hasMessage(MAP_NOT_FOUND.getMessage());
    }

    @Test
    @DisplayName("지도 수정 실패 - 맵 멤버 아님")
    void updateMap_NotMapMember() {
        UpdateMapRequestDto request = new UpdateMapRequestDto("Updated", "Desc", "Solo", null, null);

        when(mapRepository.findById(1L)).thenReturn(Optional.of(testMap));
        when(mapMemberRepository.findByMap_MapIdAndUser_UserId(1L, 99L)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> mapService.updateMap(1L, request, 99L))
                .isInstanceOf(MapException.class)
                .hasMessage(NOT_MAP_MEMBER.getMessage());
    }

    @Test
    @DisplayName("친구 초대 실패 - 친구 아님")
    void inviteFriend_NotFriend() {
        Long mapId = 1L;
        Long userId = 1L;
        InviteFriendRequestDto request = new InviteFriendRequestDto(2L);

        when(userRepository.findById(userId)).thenReturn(Optional.of(testUser));
        when(mapMemberRepository.findByMap_MapIdAndUser_UserId(mapId, userId)).thenReturn(Optional.of(testMapMember));
        when(userRepository.findById(2L)).thenReturn(Optional.of(friendUser));
        when(friendshipRepository.existsFriendship(testUser, friendUser, FriendshipStatus.ACCEPTED)).thenReturn(false);

        assertThatThrownBy(() -> mapService.inviteFriend(mapId, request, userId))
                .isInstanceOf(FriendException.class)
                .hasMessage(INVALID_FRIENDSHIP_ID.getMessage());
    }

    @Test
    @DisplayName("친구 초대 실패 - 초대 대상 유저 없음")
    void inviteFriend_FriendUserNotFound() {
        Long mapId = 1L;
        Long userId = 1L;
        InviteFriendRequestDto request = new InviteFriendRequestDto(99L);

        when(userRepository.findById(userId)).thenReturn(Optional.of(testUser));
        when(mapMemberRepository.findByMap_MapIdAndUser_UserId(mapId, userId)).thenReturn(Optional.of(testMapMember));
        when(userRepository.findById(99L)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> mapService.inviteFriend(mapId, request, userId))
                .isInstanceOf(UserException.class)
                .hasMessage(USER_NOT_FOUND.getMessage());
    }

    @Test
    @DisplayName("친구 초대 실패 - DB 충돌 시 MAP_INVITATION_CONFLICT")
    void inviteFriend_ConflictOnSave() {
        Long mapId = 1L;
        Long userId = 1L;
        InviteFriendRequestDto request = new InviteFriendRequestDto(2L);

        when(userRepository.findById(userId)).thenReturn(Optional.of(testUser));
        when(mapMemberRepository.findByMap_MapIdAndUser_UserId(mapId, userId)).thenReturn(Optional.of(testMapMember));
        when(userRepository.findById(2L)).thenReturn(Optional.of(friendUser));
        when(friendshipRepository.existsFriendship(testUser, friendUser, FriendshipStatus.ACCEPTED)).thenReturn(true);
        when(mapMemberRepository.findByMap_MapIdAndUser_UserId(mapId, 2L)).thenReturn(Optional.empty());
        doThrow(new org.springframework.dao.DataIntegrityViolationException("duplicate"))
                .when(mapMemberRepository).flush();

        assertThatThrownBy(() -> mapService.inviteFriend(mapId, request, userId))
                .isInstanceOf(MapException.class)
                .hasMessage(MAP_INVITATION_CONFLICT.getMessage());
    }

    @Test
    @DisplayName("초대 수락 실패 - 이미 PENDING이 아닌 초대")
    void acceptInvitation_NotPending() {
        Long mapMemberId = 1L;
        Long userId = 1L;
        MapMember acceptedMember = MapMember.from(testMap, testUser, friendUser, MapMemberRole.EDITOR);

        when(userRepository.findById(userId)).thenReturn(Optional.of(testUser));
        when(mapMemberRepository.findById(mapMemberId)).thenReturn(Optional.of(acceptedMember));

        assertThatThrownBy(() -> mapService.acceptInvitation(mapMemberId, userId))
                .isInstanceOf(MapException.class)
                .hasMessage(INVITATION_NOT_FOUND.getMessage());
    }

    @Test
    @DisplayName("초대 거절 실패 - 이미 PENDING이 아닌 초대")
    void rejectInvitation_NotPending() {
        Long mapMemberId = 1L;
        Long userId = 1L;
        MapMember acceptedMember = MapMember.from(testMap, testUser, friendUser, MapMemberRole.EDITOR);

        when(userRepository.findById(userId)).thenReturn(Optional.of(testUser));
        when(mapMemberRepository.findById(mapMemberId)).thenReturn(Optional.of(acceptedMember));

        assertThatThrownBy(() -> mapService.rejectInvitation(mapMemberId, userId))
                .isInstanceOf(MapException.class)
                .hasMessage(INVITATION_NOT_FOUND.getMessage());
    }

    @Test
    @DisplayName("지도 상세 조회 성공")
    void getMapDetail_Success() {
        Long mapId = 1L;
        Long userId = 1L;

        when(mapMemberRepository.findByMap_MapIdAndUser_UserId(mapId, userId)).thenReturn(Optional.of(testMapMember));
        when(mapMemberRepository.countByMap_MapIdAndMapMemberRoleNot(mapId, MapMemberRole.PENDING)).thenReturn(2L);

        MapInfoDto result = mapService.getMapDetail(mapId, userId);

        assertThat(result.getMapName()).isEqualTo("Test Map");
        assertThat(result.getMyRole()).isEqualTo(MapMemberRole.OWNER);
        assertThat(result.getMemberCount()).isEqualTo(2);
    }

    @Test
    @DisplayName("지도 상세 조회 실패 - PENDING 멤버")
    void getMapDetail_PendingMember() {
        Long mapId = 1L;
        Long userId = 1L;
        MapMember pendingMember = MapMember.from(testMap, testUser, friendUser, MapMemberRole.PENDING);

        when(mapMemberRepository.findByMap_MapIdAndUser_UserId(mapId, userId)).thenReturn(Optional.of(pendingMember));

        assertThatThrownBy(() -> mapService.getMapDetail(mapId, userId))
                .isInstanceOf(MapException.class)
                .hasMessage(NOT_MAP_MEMBER.getMessage());
    }

    @Test
    @DisplayName("지도 멤버 목록 조회 성공")
    void getMapMembers_Success() {
        Long mapId = 1L;
        Long userId = 1L;
        MapMember editorMember = MapMember.from(testMap, friendUser, MapMemberRole.EDITOR);

        when(mapMemberRepository.findByMap_MapIdAndUser_UserId(mapId, userId)).thenReturn(Optional.of(testMapMember));
        when(mapMemberRepository.findAllByMap_MapIdAndMapMemberRoleNot(mapId, MapMemberRole.PENDING))
                .thenReturn(List.of(testMapMember, editorMember));

        List<MapMemberDto> result = mapService.getMapMembers(mapId, userId);

        assertThat(result).hasSize(2);
    }

    @Test
    @DisplayName("지도 멤버 목록 조회 실패 - 맵 멤버 아님")
    void getMapMembers_NotMapMember() {
        when(mapMemberRepository.findByMap_MapIdAndUser_UserId(1L, 99L)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> mapService.getMapMembers(1L, 99L))
                .isInstanceOf(MapException.class)
                .hasMessage(NOT_MAP_MEMBER.getMessage());
    }
}
