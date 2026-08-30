package com.couplemap.memory.service;

import com.couplemap.global.exception.exceptions.MapException;
import com.couplemap.global.exception.exceptions.MemoryException;
import com.couplemap.global.exception.exceptions.S3Exception;
import com.couplemap.global.exception.exceptions.UserException;
import com.couplemap.global.filecleanup.FileCleanupService;
import com.couplemap.global.s3.S3Service;
import com.couplemap.map.domain.Map;
import com.couplemap.map.domain.MapMember;
import com.couplemap.map.domain.MapMemberRole;
import com.couplemap.map.repository.MapMemberRepository;
import com.couplemap.map.repository.MapRepository;
import com.couplemap.mediafile.domain.MediaFile;
import com.couplemap.mediafile.domain.MediaFileType;
import com.couplemap.mediafile.repository.MediaFileRepository;
import com.couplemap.memory.domain.Memory;
import com.couplemap.memory.domain.UploadSession;
import com.couplemap.memory.dto.*;
import com.couplemap.memory.repository.MemoryRepository;
import com.couplemap.memory.repository.UploadSessionRepository;
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
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Slice;
import org.springframework.data.domain.SliceImpl;
import org.springframework.test.util.ReflectionTestUtils;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.Collections;
import java.util.List;
import java.util.Optional;

import static com.couplemap.global.exception.code.MapErrorCode.NOT_MAP_MEMBER;
import static com.couplemap.global.exception.code.MemoryErrorCode.*;
import static com.couplemap.global.exception.code.UserErrorCode.USER_NOT_FOUND;
import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
@DisplayName("MemoryServiceImpl 단위 테스트")
class MemoryServiceUnitTest {

    @Mock private MemoryRepository memoryRepository;
    @Mock private MapRepository mapRepository;
    @Mock private UserRepository userRepository;
    @Mock private MapMemberRepository mapMemberRepository;
    @Mock private S3Service s3Service;
    @Mock private FileCleanupService fileCleanupService;
    @Mock private MediaFileRepository mediaFileRepository;
    @Mock private UploadSessionRepository uploadSessionRepository;

    @InjectMocks
    private MemoryServiceImpl memoryService;

    private User testUser;
    private User anotherUser;
    private Map testMap;
    private MapMember ownerMember;
    private MapMember editorMember;
    private Memory testMemory;

    @BeforeEach
    void setUp() {
        testUser = User.builder()
                .loginType("KAKAO").providerId("TEST1").email("test@test.com")
                .name("테스트유저").role(UserRole.USER).friendCode("CODE1")
                .build();
        ReflectionTestUtils.setField(testUser, "userId", 1L);

        anotherUser = User.builder()
                .loginType("KAKAO").providerId("TEST2").email("other@test.com")
                .name("다른유저").role(UserRole.USER).friendCode("CODE2")
                .build();
        ReflectionTestUtils.setField(anotherUser, "userId", 2L);

        testMap = Map.from("테스트맵", "설명", "Solo");
        ReflectionTestUtils.setField(testMap, "mapId", 10L);

        ownerMember = MapMember.from(testMap, testUser, MapMemberRole.OWNER);
        editorMember = MapMember.from(testMap, anotherUser, MapMemberRole.EDITOR);

        CreateMemoryRequestDto req = new CreateMemoryRequestDto(
                "테스트 추억", "내용", "장소", null,
                LocalDate.of(2024, 1, 1),
                new BigDecimal("37.5665"), new BigDecimal("126.9780"), null);
        testMemory = Memory.from(req, testMap, testUser);
        ReflectionTestUtils.setField(testMemory, "memoryId", 100L);
    }

    // ==================== createMemory ====================

    @Test
    @DisplayName("추억 생성 성공 - 파일 없음")
    void createMemory_Success_NoFiles() {
        CreateMemoryRequestDto request = new CreateMemoryRequestDto(
                "새 추억", "내용", "장소", null,
                LocalDate.of(2024, 3, 15),
                new BigDecimal("37.1234"), new BigDecimal("127.5678"), null);

        when(userRepository.findById(1L)).thenReturn(Optional.of(testUser));
        when(mapMemberRepository.findByMap_MapIdAndUser_UserId(10L, 1L)).thenReturn(Optional.of(ownerMember));
        when(mapRepository.findById(10L)).thenReturn(Optional.of(testMap));
        when(memoryRepository.save(any(Memory.class))).thenAnswer(inv -> {
            Memory m = inv.getArgument(0);
            ReflectionTestUtils.setField(m, "memoryId", 200L);
            return m;
        });

        Long result = memoryService.createMemory(10L, request, 1L);

        assertThat(result).isEqualTo(200L);
        verify(memoryRepository).save(any(Memory.class));
        verify(mediaFileRepository, never()).save(any());
    }

    @Test
    @DisplayName("완료 통보 성공 - 세션의 fileKey로 MediaFile을 만든다")
    void completeUpload_Success() {
        CreateMemoryRequestDto request = new CreateMemoryRequestDto(
                "새 추억", "내용", "장소", null,
                LocalDate.of(2024, 3, 15),
                new BigDecimal("37.1234"), new BigDecimal("127.5678"), null);

        UploadSession session = UploadSession.of("upload-1", 1L, 10L, UploadSession.PURPOSE_MEMORY,
                List.of(new UploadSession.UploadFile("memory/a.jpg", "a.jpg", "image/jpeg", 1024L)), 3600);

        when(userRepository.findById(1L)).thenReturn(Optional.of(testUser));
        when(mapMemberRepository.findByMap_MapIdAndUser_UserId(10L, 1L)).thenReturn(Optional.of(ownerMember));
        when(mapRepository.findById(10L)).thenReturn(Optional.of(testMap));
        when(memoryRepository.save(any(Memory.class))).thenAnswer(inv -> inv.getArgument(0));
        when(uploadSessionRepository.findById("upload-1")).thenReturn(Optional.of(session));

        memoryService.completeUpload(10L, new CompleteUploadRequestDto("upload-1", request,
                List.of(new CompleteUploadRequestDto.FileRef("memory/a.jpg", 1))), 1L);

        verify(mediaFileRepository).saveAll(anyList());
        // 실제로 쓴 키는 고아 회수 예약을 푼다
        verify(fileCleanupService).cancelPendingUpload(List.of("memory/a.jpg"));
        verify(uploadSessionRepository).deleteById("upload-1");
    }

    @Test
    @DisplayName("완료 통보 실패 - 세션에 없는 fileKey는 거부한다")
    void completeUpload_ForeignKeyRejected() {
        CreateMemoryRequestDto request = new CreateMemoryRequestDto(
                "새 추억", "내용", "장소", null,
                LocalDate.of(2024, 3, 15),
                new BigDecimal("37.1234"), new BigDecimal("127.5678"), null);

        UploadSession session = UploadSession.of("upload-1", 1L, 10L, UploadSession.PURPOSE_MEMORY,
                List.of(new UploadSession.UploadFile("memory/a.jpg", "a.jpg", "image/jpeg", 1024L)), 3600);

        when(userRepository.findById(1L)).thenReturn(Optional.of(testUser));
        when(mapMemberRepository.findByMap_MapIdAndUser_UserId(10L, 1L)).thenReturn(Optional.of(ownerMember));
        when(mapRepository.findById(10L)).thenReturn(Optional.of(testMap));
        when(memoryRepository.save(any(Memory.class))).thenAnswer(inv -> inv.getArgument(0));
        when(uploadSessionRepository.findById("upload-1")).thenReturn(Optional.of(session));

        assertThatThrownBy(() -> memoryService.completeUpload(10L,
                new CompleteUploadRequestDto("upload-1", request,
                        List.of(new CompleteUploadRequestDto.FileRef("memory/stolen.jpg", 1))), 1L))
                .isInstanceOf(S3Exception.class);
    }

    @Test
    @DisplayName("완료 통보 실패 - 만료된 세션")
    void completeUpload_SessionNotFound() {
        CreateMemoryRequestDto request = new CreateMemoryRequestDto(
                "새 추억", "내용", "장소", null,
                LocalDate.of(2024, 3, 15),
                new BigDecimal("37.1234"), new BigDecimal("127.5678"), null);

        when(userRepository.findById(1L)).thenReturn(Optional.of(testUser));
        when(mapMemberRepository.findByMap_MapIdAndUser_UserId(10L, 1L)).thenReturn(Optional.of(ownerMember));
        when(mapRepository.findById(10L)).thenReturn(Optional.of(testMap));
        when(uploadSessionRepository.findById("gone")).thenReturn(Optional.empty());

        assertThatThrownBy(() -> memoryService.completeUpload(10L,
                new CompleteUploadRequestDto("gone", request, List.of()), 1L))
                .isInstanceOf(S3Exception.class);
    }

    @Test
    @DisplayName("추억 생성 실패 - 유저 없음")
    void createMemory_UserNotFound() {
        CreateMemoryRequestDto request = new CreateMemoryRequestDto(
                "추억", null, "장소", null, LocalDate.now(),
                BigDecimal.ZERO, BigDecimal.ZERO, null);

        when(userRepository.findById(99L)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> memoryService.createMemory(10L, request, 99L))
                .isInstanceOf(UserException.class)
                .hasMessage(USER_NOT_FOUND.getMessage());
    }

    @Test
    @DisplayName("추억 생성 실패 - 맵 멤버 아님")
    void createMemory_NotMapMember() {
        CreateMemoryRequestDto request = new CreateMemoryRequestDto(
                "추억", null, "장소", null, LocalDate.now(),
                BigDecimal.ZERO, BigDecimal.ZERO, null);

        when(userRepository.findById(1L)).thenReturn(Optional.of(testUser));
        when(mapMemberRepository.findByMap_MapIdAndUser_UserId(10L, 1L)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> memoryService.createMemory(10L, request, 1L))
                .isInstanceOf(MapException.class)
                .hasMessage(NOT_MAP_MEMBER.getMessage());
    }

    @Test
    @DisplayName("추억 생성 실패 - PENDING 멤버")
    void createMemory_PendingMember() {
        CreateMemoryRequestDto request = new CreateMemoryRequestDto(
                "추억", null, "장소", null, LocalDate.now(),
                BigDecimal.ZERO, BigDecimal.ZERO, null);
        MapMember pendingMember = MapMember.from(testMap, testUser, anotherUser, MapMemberRole.PENDING);

        when(userRepository.findById(1L)).thenReturn(Optional.of(testUser));
        when(mapMemberRepository.findByMap_MapIdAndUser_UserId(10L, 1L)).thenReturn(Optional.of(pendingMember));

        assertThatThrownBy(() -> memoryService.createMemory(10L, request, 1L))
                .isInstanceOf(MapException.class)
                .hasMessage(NOT_MAP_MEMBER.getMessage());
    }

    @Test
    @DisplayName("추억 생성 실패 - 맵 없음")
    void createMemory_MapNotFound() {
        CreateMemoryRequestDto request = new CreateMemoryRequestDto(
                "추억", null, "장소", null, LocalDate.now(),
                BigDecimal.ZERO, BigDecimal.ZERO, null);

        when(userRepository.findById(1L)).thenReturn(Optional.of(testUser));
        when(mapMemberRepository.findByMap_MapIdAndUser_UserId(10L, 1L)).thenReturn(Optional.of(ownerMember));
        when(mapRepository.findById(10L)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> memoryService.createMemory(10L, request, 1L))
                .isInstanceOf(MapException.class);
    }

    // ==================== deleteMemory ====================

    @Test
    @DisplayName("추억 삭제 성공 - fileCleanupService 호출 검증")
    void deleteMemory_Success() {
        MediaFile mf = MediaFile.builder()
                .fileKey("media/key1").originalFilename("test.jpg")
                .mediaFileType(MediaFileType.IMAGE).fileSize(100L).displayOrder(1)
                .build();

        when(mapMemberRepository.findByMap_MapIdAndUser_UserId(10L, 1L)).thenReturn(Optional.of(ownerMember));
        when(memoryRepository.findById(100L)).thenReturn(Optional.of(testMemory));
        when(mediaFileRepository.findByMemoryId(100L)).thenReturn(List.of(mf));

        memoryService.deleteMemory(10L, 100L, 1L);

        verify(fileCleanupService).scheduleDeleteAll(List.of("media/key1"));
        verify(mediaFileRepository).deleteAll(List.of(mf));
        verify(memoryRepository).delete(testMemory);
    }

    @Test
    @DisplayName("추억 삭제 실패 - 작성자 아님")
    void deleteMemory_NotAuthor() {
        when(mapMemberRepository.findByMap_MapIdAndUser_UserId(10L, 2L)).thenReturn(Optional.of(editorMember));
        when(memoryRepository.findById(100L)).thenReturn(Optional.of(testMemory));

        assertThatThrownBy(() -> memoryService.deleteMemory(10L, 100L, 2L))
                .isInstanceOf(MemoryException.class)
                .hasMessage(NO_PERMISSION_TO_DELETE.getMessage());
    }

    @Test
    @DisplayName("추억 삭제 실패 - 맵 멤버 아님")
    void deleteMemory_NotMapMember() {
        when(mapMemberRepository.findByMap_MapIdAndUser_UserId(10L, 99L)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> memoryService.deleteMemory(10L, 100L, 99L))
                .isInstanceOf(MapException.class)
                .hasMessage(NOT_MAP_MEMBER.getMessage());
    }

    @Test
    @DisplayName("추억 삭제 실패 - 존재하지 않는 추억")
    void deleteMemory_NotFound() {
        when(mapMemberRepository.findByMap_MapIdAndUser_UserId(10L, 1L)).thenReturn(Optional.of(ownerMember));
        when(memoryRepository.findById(999L)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> memoryService.deleteMemory(10L, 999L, 1L))
                .isInstanceOf(MemoryException.class)
                .hasMessage(MEMORY_NOT_FOUND.getMessage());
    }

    // ==================== updateMemory ====================

    @Test
    @DisplayName("추억 수정 성공 - 파일 삭제 + 새 파일 추가")
    void updateMemory_Success_DeleteAndAddFiles() {
        MediaFile existingFile = MediaFile.builder()
                .fileKey("old/key").originalFilename("old.jpg")
                .mediaFileType(MediaFileType.IMAGE).fileSize(100L).displayOrder(1)
                .build();
        ReflectionTestUtils.setField(existingFile, "mediaFileId", 50L);

        UploadSession session = UploadSession.of("upload-1", 1L, 10L, UploadSession.PURPOSE_MEMORY,
                List.of(new UploadSession.UploadFile("memory/new.jpg", "new.jpg", "image/jpeg", 1024L)), 3600);

        UpdateMemoryRequestDto request = new UpdateMemoryRequestDto(
                "수정 제목", "수정 내용", "수정 장소",
                LocalDate.of(2024, 5, 1), null, List.of(50L),
                "upload-1", List.of(new CompleteUploadRequestDto.FileRef("memory/new.jpg", 1)));

        when(mapMemberRepository.findByMap_MapIdAndUser_UserId(10L, 1L)).thenReturn(Optional.of(ownerMember));
        when(memoryRepository.findById(100L)).thenReturn(Optional.of(testMemory));
        when(mediaFileRepository.findAllByIdsAndMemoryId(List.of(50L), 100L)).thenReturn(List.of(existingFile));
        when(mediaFileRepository.findByMemoryIdOrderByDisplayOrder(100L)).thenReturn(List.of());
        when(uploadSessionRepository.findById("upload-1")).thenReturn(Optional.of(session));

        Long result = memoryService.updateMemory(10L, 100L, request, 1L);

        assertThat(result).isEqualTo(100L);
        verify(fileCleanupService).scheduleDeleteAll(List.of("old/key"));
        verify(mediaFileRepository).deleteAll(List.of(existingFile));
        verify(mediaFileRepository).saveAll(anyList());
        verify(fileCleanupService).cancelPendingUpload(List.of("memory/new.jpg"));
    }

    @Test
    @DisplayName("추억 수정 성공 - displayOrder 이어붙기")
    void updateMemory_Success_DisplayOrderContinues() {
        MediaFile existing = MediaFile.builder()
                .fileKey("key").originalFilename("a.jpg")
                .mediaFileType(MediaFileType.IMAGE).fileSize(100L).displayOrder(3)
                .build();

        UploadSession session = UploadSession.of("upload-1", 1L, 10L, UploadSession.PURPOSE_MEMORY,
                List.of(new UploadSession.UploadFile("memory/b.jpg", "b.jpg", "image/jpeg", 1024L)), 3600);

        UpdateMemoryRequestDto request = new UpdateMemoryRequestDto(
                "수정", null, "장소", LocalDate.now(), null, null,
                "upload-1", List.of(new CompleteUploadRequestDto.FileRef("memory/b.jpg", 1)));

        when(mapMemberRepository.findByMap_MapIdAndUser_UserId(10L, 1L)).thenReturn(Optional.of(ownerMember));
        when(memoryRepository.findById(100L)).thenReturn(Optional.of(testMemory));
        when(mediaFileRepository.findByMemoryIdOrderByDisplayOrder(100L)).thenReturn(List.of(existing));
        when(uploadSessionRepository.findById("upload-1")).thenReturn(Optional.of(session));

        memoryService.updateMemory(10L, 100L, request, 1L);

        // 요청의 displayOrder가 아니라 기존 최대값 다음부터 매긴다
        verify(mediaFileRepository).saveAll(argThat(files -> {
            List<MediaFile> list = (List<MediaFile>) files;
            return list.size() == 1 && list.get(0).getDisplayOrder() == 4;
        }));
    }

    @Test
    @DisplayName("추억 수정 실패 - 작성자 아님")
    void updateMemory_NotAuthor() {
        UpdateMemoryRequestDto request = new UpdateMemoryRequestDto(
                "수정", null, "장소", LocalDate.now(), null, null, null, null);

        when(mapMemberRepository.findByMap_MapIdAndUser_UserId(10L, 2L)).thenReturn(Optional.of(editorMember));
        when(memoryRepository.findById(100L)).thenReturn(Optional.of(testMemory));

        assertThatThrownBy(() -> memoryService.updateMemory(10L, 100L, request, 2L))
                .isInstanceOf(MemoryException.class)
                .hasMessage(NO_PERMISSION_TO_UPDATE.getMessage());
    }

    @Test
    @DisplayName("추억 수정 실패 - 다른 맵의 memoryId")
    void updateMemory_WrongMap() {
        Map otherMap = Map.from("다른맵", "설명", "Solo");
        ReflectionTestUtils.setField(otherMap, "mapId", 20L);
        Memory otherMemory = Memory.from(
                new CreateMemoryRequestDto("제목", null, "장소", null, LocalDate.now(),
                        BigDecimal.ZERO, BigDecimal.ZERO, null),
                otherMap, testUser);
        ReflectionTestUtils.setField(otherMemory, "memoryId", 200L);

        UpdateMemoryRequestDto request = new UpdateMemoryRequestDto(
                "수정", null, "장소", LocalDate.now(), null, null, null, null);

        when(mapMemberRepository.findByMap_MapIdAndUser_UserId(10L, 1L)).thenReturn(Optional.of(ownerMember));
        when(memoryRepository.findById(200L)).thenReturn(Optional.of(otherMemory));

        assertThatThrownBy(() -> memoryService.updateMemory(10L, 200L, request, 1L))
                .isInstanceOf(MemoryException.class)
                .hasMessage(MEMORY_NOT_FOUND.getMessage());
    }

    @Test
    @DisplayName("추억 수정 실패 - 잘못된 deleteFileIds")
    void updateMemory_InvalidDeleteFileIds() {
        UpdateMemoryRequestDto request = new UpdateMemoryRequestDto(
                "수정", null, "장소", LocalDate.now(), null, List.of(50L, 51L), null, null);

        when(mapMemberRepository.findByMap_MapIdAndUser_UserId(10L, 1L)).thenReturn(Optional.of(ownerMember));
        when(memoryRepository.findById(100L)).thenReturn(Optional.of(testMemory));
        when(mediaFileRepository.findAllByIdsAndMemoryId(List.of(50L, 51L), 100L)).thenReturn(List.of());

        assertThatThrownBy(() -> memoryService.updateMemory(10L, 100L, request, 1L))
                .isInstanceOf(MemoryException.class)
                .hasMessage(INVALID_MEDIA_FILE.getMessage());
    }

    // ==================== getMemoryList ====================

    @Test
    @DisplayName("추억 목록 조회 성공")
    void getMemoryList_Success() {
        PageRequest pageable = PageRequest.of(0, 10);
        Slice<Memory> slice = new SliceImpl<>(List.of(testMemory), pageable, false);

        when(mapMemberRepository.findByMap_MapIdAndUser_UserId(10L, 1L)).thenReturn(Optional.of(ownerMember));
        when(memoryRepository.findByMap_MapId(10L, pageable)).thenReturn(slice);
        when(mediaFileRepository.findByMemoryIdIn(List.of(100L))).thenReturn(List.of());

        Slice<MemoryListResponseDto> result = memoryService.getMemoryList(10L, 1L, pageable);

        assertThat(result.getContent()).hasSize(1);
        assertThat(result.getContent().get(0).getTitle()).isEqualTo("테스트 추억");
    }

    @Test
    @DisplayName("추억 목록 조회 실패 - 맵 멤버 아님")
    void getMemoryList_NotMapMember() {
        when(mapMemberRepository.findByMap_MapIdAndUser_UserId(10L, 99L)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> memoryService.getMemoryList(10L, 99L, PageRequest.of(0, 10)))
                .isInstanceOf(MapException.class)
                .hasMessage(NOT_MAP_MEMBER.getMessage());
    }

    // ==================== getMemoryDetail ====================

    @Test
    @DisplayName("추억 상세 조회 성공")
    void getMemoryDetail_Success() {
        when(mapMemberRepository.findByMap_MapIdAndUser_UserId(10L, 1L)).thenReturn(Optional.of(ownerMember));
        when(memoryRepository.findById(100L)).thenReturn(Optional.of(testMemory));
        when(mediaFileRepository.findByMemoryIdOrderByDisplayOrder(100L)).thenReturn(List.of());

        MemoryDetailResponseDto result = memoryService.getMemoryDetail(10L, 100L, 1L);

        assertThat(result.getTitle()).isEqualTo("테스트 추억");
        assertThat(result.getMediaFiles()).isEmpty();
    }

    @Test
    @DisplayName("추억 상세 조회 실패 - 맵 멤버 아님")
    void getMemoryDetail_NotMapMember() {
        when(mapMemberRepository.findByMap_MapIdAndUser_UserId(10L, 99L)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> memoryService.getMemoryDetail(10L, 100L, 99L))
                .isInstanceOf(MapException.class)
                .hasMessage(NOT_MAP_MEMBER.getMessage());
    }

    // ==================== getMemoryMarkers ====================

    @Test
    @DisplayName("추억 마커 조회 성공")
    void getMemoryMarkers_Success() {
        when(mapMemberRepository.findByMap_MapIdAndUser_UserId(10L, 1L)).thenReturn(Optional.of(ownerMember));
        when(memoryRepository.findMarkersByMapId(10L)).thenReturn(List.of(
                new MemoryMarkerResponseDto(100L, new BigDecimal("37.5665"), new BigDecimal("126.9780"),
                        "카페", LocalDate.of(2024, 1, 1))));

        List<MemoryMarkerResponseDto> result = memoryService.getMemoryMarkers(10L, 1L);

        assertThat(result).hasSize(1);
        assertThat(result.get(0).getMemoryId()).isEqualTo(100L);
        assertThat(result.get(0).getLatitude()).isEqualByComparingTo(new BigDecimal("37.5665"));
    }

    @Test
    @DisplayName("추억 마커 조회 실패 - 맵 멤버 아님")
    void getMemoryMarkers_NotMapMember() {
        when(mapMemberRepository.findByMap_MapIdAndUser_UserId(10L, 99L)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> memoryService.getMemoryMarkers(10L, 99L))
                .isInstanceOf(MapException.class)
                .hasMessage(NOT_MAP_MEMBER.getMessage());
    }
}
