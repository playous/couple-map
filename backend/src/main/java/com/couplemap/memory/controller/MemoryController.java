package com.couplemap.memory.controller;

import com.couplemap.global.response.ApiResponse;
import com.couplemap.memory.dto.*;
import com.couplemap.memory.service.MemoryService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Slice;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.*;

import java.net.URI;
import java.util.List;

@Tag(name = "Memory", description = "추억 관리 API")
@RestController
@RequiredArgsConstructor
@RequestMapping("/api/maps/{mapId}/memories")
public class MemoryController {

    private final MemoryService memoryService;

    @Operation(summary = "추억 생성", description = "파일 없는 추억을 생성합니다. 파일이 있으면 /uploads 후 /complete를 사용합니다.")
    @PostMapping
    public ResponseEntity<ApiResponse<Long>> createMemory(
            @PathVariable Long mapId,
            @Valid @RequestBody CreateMemoryRequestDto request,
            @AuthenticationPrincipal(expression = "userId") Long userId) {
        Long memoryId = memoryService.createMemory(mapId, request, userId);
        return ResponseEntity.created(URI.create("/api/maps/" + mapId + "/memories/" + memoryId))
                .body(ApiResponse.success(memoryId, "추억이 성공적으로 생성되었습니다."));
    }

    @Operation(summary = "업로드 URL 발급", description = "파일을 S3에 직접 업로드할 presigned URL을 발급합니다.")
    @PostMapping("/uploads")
    public ResponseEntity<ApiResponse<UploadUrlResponseDto>> issueUploadUrls(
            @PathVariable Long mapId,
            @Valid @RequestBody UploadUrlRequestDto request,
            @AuthenticationPrincipal(expression = "userId") Long userId) {
        UploadUrlResponseDto response = memoryService.issueUploadUrls(mapId, request, userId);
        return ResponseEntity.ok(ApiResponse.success(response, "업로드 URL이 발급되었습니다."));
    }

    @Operation(summary = "업로드 완료", description = "S3 업로드를 마친 파일 키와 추억 정보를 받아 저장합니다.")
    @PostMapping("/complete")
    public ResponseEntity<ApiResponse<Long>> completeUpload(
            @PathVariable Long mapId,
            @Valid @RequestBody CompleteUploadRequestDto request,
            @AuthenticationPrincipal(expression = "userId") Long userId) {
        Long memoryId = memoryService.completeUpload(mapId, request, userId);
        return ResponseEntity.created(URI.create("/api/maps/" + mapId + "/memories/" + memoryId))
                .body(ApiResponse.success(memoryId, "추억이 성공적으로 생성되었습니다."));
    }

    /** 페이지 크기 상한 — size만큼 IN 절 파라미터가 생성되므로(썸네일 일괄 조회) 반드시 제한한다. */
    private static final int MAX_PAGE_SIZE = 100;

    @Operation(summary = "추억 목록 조회", description = "특정 지도에 속한 추억 목록을 페이징으로 조회합니다.")
    @GetMapping
    public ResponseEntity<ApiResponse<Slice<MemoryListResponseDto>>> getMemoryList(
            @PathVariable Long mapId,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "10") int size,
            @AuthenticationPrincipal(expression = "userId") Long userId) {
        // clamp 방식 선택 이유:
        //  - size=0/음수는 PageRequest.of가 IllegalArgumentException을 던져 미처리 500이 됐다
        //  - size 상한이 없으면 ?size=10000 한 번으로 IN 절 파라미터 1만 개짜리 쿼리가 나간다
        //  - 예외 대신 보정하면 잘못된 입력이 5xx(서버 장애로 오인)로 승격되지 않는다
        int safePage = Math.max(page, 0);
        int safeSize = Math.min(Math.max(size, 1), MAX_PAGE_SIZE);
        Slice<MemoryListResponseDto> memoryList =
                memoryService.getMemoryList(mapId, userId, PageRequest.of(safePage, safeSize));
        return ResponseEntity.ok(ApiResponse.success(memoryList, "추억 목록 조회가 완료되었습니다."));
    }

    @Operation(summary = "추억 마커 조회", description = "지도에 표시할 추억 마커 목록을 조회합니다.")
    @GetMapping("/markers")
    public ResponseEntity<ApiResponse<List<MemoryMarkerResponseDto>>> getMemoryMarkers(
            @PathVariable Long mapId,
            @AuthenticationPrincipal(expression = "userId") Long userId) {
        List<MemoryMarkerResponseDto> markers = memoryService.getMemoryMarkers(mapId, userId);
        return ResponseEntity.ok(ApiResponse.success(markers, "추억 마커 조회가 완료되었습니다."));
    }

    @Operation(summary = "추억 상세 조회", description = "특정 추억의 상세 정보를 조회합니다.")
    @GetMapping("/{memoryId}")
    public ResponseEntity<ApiResponse<MemoryDetailResponseDto>> getMemoryDetail(
            @PathVariable Long mapId,
            @PathVariable Long memoryId,
            @AuthenticationPrincipal(expression = "userId") Long userId) {
        MemoryDetailResponseDto memoryDetail = memoryService.getMemoryDetail(mapId, memoryId, userId);
        return ResponseEntity.ok(ApiResponse.success(memoryDetail, "추억 상세 조회가 완료되었습니다."));
    }

    @Operation(summary = "추억 삭제", description = "추억을 삭제합니다. 작성자만 삭제할 수 있습니다.")
    @DeleteMapping("/{memoryId}")
    public ResponseEntity<ApiResponse<Void>> deleteMemory(
            @PathVariable Long mapId,
            @PathVariable Long memoryId,
            @AuthenticationPrincipal(expression = "userId") Long userId) {
        memoryService.deleteMemory(mapId, memoryId, userId);
        return ResponseEntity.ok(ApiResponse.success("추억이 성공적으로 삭제되었습니다."));
    }

    @Operation(summary = "추억 수정", description = "추억을 수정합니다. 작성자만 수정할 수 있습니다.")
    @PutMapping("/{memoryId}")
    public ResponseEntity<ApiResponse<Long>> updateMemory(
            @PathVariable Long mapId,
            @PathVariable Long memoryId,
            @Valid @RequestBody UpdateMemoryRequestDto request,
            @AuthenticationPrincipal(expression = "userId") Long userId) {
        Long updatedMemoryId = memoryService.updateMemory(mapId, memoryId, request, userId);
        return ResponseEntity.ok(ApiResponse.success(updatedMemoryId, "추억이 성공적으로 수정되었습니다."));
    }
}
