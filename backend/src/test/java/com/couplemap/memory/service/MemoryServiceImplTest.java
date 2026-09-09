package com.couplemap.memory.service;

import com.couplemap.friend.repository.FriendshipRepository;
import com.couplemap.global.exception.exceptions.MemoryException;
import com.couplemap.map.domain.Map;
import com.couplemap.map.domain.MapMember;
import com.couplemap.map.domain.MapMemberRole;
import com.couplemap.map.repository.MapMemberRepository;
import com.couplemap.map.repository.MapRepository;
import com.couplemap.mediafile.repository.MediaFileRepository;
import com.couplemap.memory.domain.Memory;
import com.couplemap.memory.dto.CalendarMemoryResponseDto;
import com.couplemap.memory.dto.CompleteUploadRequestDto;
import com.couplemap.memory.dto.CreateMemoryRequestDto;
import com.couplemap.memory.dto.MemoryDetailResponseDto;
import com.couplemap.memory.dto.UploadUrlRequestDto;
import com.couplemap.memory.dto.UploadUrlResponseDto;
import com.couplemap.memory.repository.MemoryRepository;
import com.couplemap.user.domain.User;
import com.couplemap.user.domain.UserRole;
import com.couplemap.user.repository.UserRepository;
import static org.junit.jupiter.api.Assertions.assertThrows;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

@SpringBootTest
class MemoryServiceImplTest {

    @Autowired private MemoryService memoryService;
    @Autowired private MemoryRepository memoryRepository;
    @Autowired private UserRepository userRepository;
    @Autowired private MapRepository mapRepository;
    @Autowired private MapMemberRepository mapMemberRepository;
    @Autowired private MediaFileRepository mediaFileRepository;
    @Autowired private FriendshipRepository friendshipRepository;

    private User testUser;
    private Map testMap;

    @BeforeEach
    void setUp() {
        testUser = userRepository.save(User.builder()
                .email("test@example.com").name("테스트유저").friendCode("TEST1234")
                .providerId("TEST12341").loginType("KAKAO").role(UserRole.USER)
                .build());

        testMap = mapRepository.save(Map.from("테스트맵", "테스트 설명", "Solo"));
        mapMemberRepository.save(MapMember.from(testMap, testUser, MapMemberRole.OWNER));

        CreateMemoryRequestDto memoryRequest = new CreateMemoryRequestDto(
                "테스트 추억", "테스트 내용", "테스트 장소", null,
                LocalDate.of(2024, 1, 1),
                new BigDecimal("37.5665"), new BigDecimal("126.9780"), null);
        memoryRepository.save(Memory.from(memoryRequest, testMap, testUser));
    }

    @AfterEach
    void cleanup() {
        friendshipRepository.deleteAll();
        mediaFileRepository.deleteAll();
        memoryRepository.deleteAll();
        mapMemberRepository.deleteAll();
        mapRepository.deleteAll();
        userRepository.deleteAll();
    }

    @Test
    @DisplayName("통합: 발급 -> 완료로 추억 생성 후 상세 조회 시 mediaFiles 확인")
    void completeUpload_ThenGetDetail() {
        UploadUrlResponseDto issued = memoryService.issueUploadUrls(
                testMap.getMapId(),
                new UploadUrlRequestDto(List.of(
                        new UploadUrlRequestDto.FileSpec("test.png", "image/png", 1024L))),
                testUser.getUserId());

        assertThat(issued.getUploadId()).isNotBlank();
        assertThat(issued.getItems()).hasSize(1);
        assertThat(issued.getItems().get(0).getUrl()).contains("X-Amz-Signature");

        CreateMemoryRequestDto request = new CreateMemoryRequestDto(
                "파일 포함 추억", "내용", "장소", null,
                LocalDate.of(2024, 5, 1),
                new BigDecimal("37.1234"), new BigDecimal("127.5678"), null);

        Long memoryId = memoryService.completeUpload(
                testMap.getMapId(),
                new CompleteUploadRequestDto(issued.getUploadId(), request, List.of(
                        new CompleteUploadRequestDto.FileRef(issued.getItems().get(0).getFileKey(), 1))),
                testUser.getUserId());

        MemoryDetailResponseDto result = memoryService.getMemoryDetail(
                testMap.getMapId(), memoryId, testUser.getUserId());

        assertThat(result.getTitle()).isEqualTo("파일 포함 추억");
        assertThat(result.getMediaFiles()).hasSize(1);
        assertThat(result.getMediaFiles().get(0).getOriginalFilename()).isEqualTo("test.png");
        assertThat(result.getMediaFiles().get(0).getDisplayOrder()).isEqualTo(1);
        // 조회 URL은 저장값이 아니라 file_key로 서명해서 만든다
        assertThat(result.getMediaFiles().get(0).getFileUrl()).contains("X-Amz-Signature");
    }

    @Test
    @DisplayName("통합: 캘린더 조회 - 연도별 필터링 및 다중 맵")
    void getCalendarMemories_FilterByYear() {
        memoryService.createMemory(testMap.getMapId(), new CreateMemoryRequestDto(
                "2024 추억", null, "장소", null,
                LocalDate.of(2024, 6, 15),
                new BigDecimal("37.1234"), new BigDecimal("127.5678"), null
        ), testUser.getUserId());

        memoryService.createMemory(testMap.getMapId(), new CreateMemoryRequestDto(
                "2025 추억", null, "장소", null,
                LocalDate.of(2025, 3, 10),
                new BigDecimal("37.5555"), new BigDecimal("126.9999"), null
        ), testUser.getUserId());

        List<CalendarMemoryResponseDto> result2024 = memoryService.getCalendarMemories(2024, null, testUser.getUserId());

        assertThat(result2024).hasSize(2);
        assertThat(result2024).extracting("title")
                .containsExactlyInAnyOrder("테스트 추억", "2024 추억");
        assertThat(result2024).allSatisfy(dto ->
                assertThat(dto.getMemoryDate().getYear()).isEqualTo(2024));
    }

    @Test
    @DisplayName("통합: 캘린더 조회 - month를 주면 해당 월만 반환")
    void getCalendarMemories_FilterByMonth() {
        memoryService.createMemory(testMap.getMapId(), new CreateMemoryRequestDto(
                "6월 추억", null, "장소", null,
                LocalDate.of(2024, 6, 15),
                new BigDecimal("37.1234"), new BigDecimal("127.5678"), null
        ), testUser.getUserId());

        memoryService.createMemory(testMap.getMapId(), new CreateMemoryRequestDto(
                "7월 추억", null, "장소", null,
                LocalDate.of(2024, 7, 1),
                new BigDecimal("37.5555"), new BigDecimal("126.9999"), null
        ), testUser.getUserId());

        List<CalendarMemoryResponseDto> june = memoryService.getCalendarMemories(2024, 6, testUser.getUserId());

        assertThat(june).extracting("title").containsExactly("6월 추억");
        assertThat(june).allSatisfy(dto ->
                assertThat(dto.getMemoryDate().getMonthValue()).isEqualTo(6));
    }

    @Test
    @DisplayName("통합: 캘린더 조회 - 말일이 포함된다")
    void getCalendarMemories_IncludesLastDayOfMonth() {
        memoryService.createMemory(testMap.getMapId(), new CreateMemoryRequestDto(
                "2월 말일 추억", null, "장소", null,
                LocalDate.of(2024, 2, 29),
                new BigDecimal("37.1234"), new BigDecimal("127.5678"), null
        ), testUser.getUserId());

        List<CalendarMemoryResponseDto> february = memoryService.getCalendarMemories(2024, 2, testUser.getUserId());

        assertThat(february).extracting("title").contains("2월 말일 추억");
    }

    @Test
    @DisplayName("통합: 캘린더 조회 - 범위를 벗어난 month는 400")
    void getCalendarMemories_InvalidMonth() {
        assertThrows(MemoryException.class,
                () -> memoryService.getCalendarMemories(2024, 13, testUser.getUserId()));
        assertThrows(MemoryException.class,
                () -> memoryService.getCalendarMemories(2024, 0, testUser.getUserId()));
    }

    @Test
    @DisplayName("통합: 캘린더 조회 - PENDING 멤버는 제외")
    void getCalendarMemories_PendingExcluded() {
        User pendingUser = userRepository.save(User.builder()
                .email("pending@example.com").name("펜딩유저").friendCode("PEND1234")
                .providerId("PEND12341").loginType("KAKAO").role(UserRole.USER)
                .build());
        mapMemberRepository.save(MapMember.from(testMap, pendingUser, MapMemberRole.PENDING));

        List<CalendarMemoryResponseDto> result = memoryService.getCalendarMemories(2024, null, pendingUser.getUserId());

        assertThat(result).isEmpty();
    }

    @Test
    @DisplayName("통합: 캘린더 조회 - 여러 맵의 추억 합산")
    void getCalendarMemories_MultipleMapMemories() {
        Map secondMap = mapRepository.save(Map.from("두번째맵", "설명", "Friends"));
        mapMemberRepository.save(MapMember.from(secondMap, testUser, MapMemberRole.OWNER));

        memoryService.createMemory(secondMap.getMapId(), new CreateMemoryRequestDto(
                "두번째맵 추억", null, "장소", null,
                LocalDate.of(2024, 7, 20),
                new BigDecimal("35.1234"), new BigDecimal("129.5678"), null
        ), testUser.getUserId());

        List<CalendarMemoryResponseDto> result = memoryService.getCalendarMemories(2024, null, testUser.getUserId());

        assertThat(result).hasSize(2);
        assertThat(result).extracting("title")
                .containsExactlyInAnyOrder("테스트 추억", "두번째맵 추억");
    }
}
