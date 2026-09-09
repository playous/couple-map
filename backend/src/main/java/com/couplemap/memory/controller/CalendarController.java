package com.couplemap.memory.controller;

import com.couplemap.global.response.ApiResponse;
import com.couplemap.memory.dto.CalendarMemoryResponseDto;
import com.couplemap.memory.service.MemoryService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

@Tag(name = "Calendar", description = "캘린더 API")
@RestController
@RequiredArgsConstructor
@RequestMapping("/api/calendar")
public class CalendarController {

    private final MemoryService memoryService;

    @Operation(summary = "캘린더 추억 조회",
            description = "유저가 속한 모든 지도의 추억을 조회합니다. month를 주면 해당 월만, 생략하면 연도 전체를 반환합니다.")
    @GetMapping("/memories")
    public ResponseEntity<ApiResponse<List<CalendarMemoryResponseDto>>> getCalendarMemories(
            @RequestParam int year,
            @RequestParam(required = false) Integer month,
            @AuthenticationPrincipal(expression = "userId") Long userId) {
        List<CalendarMemoryResponseDto> memories = memoryService.getCalendarMemories(year, month, userId);
        return ResponseEntity.ok(ApiResponse.success(memories, "캘린더 추억 조회가 완료되었습니다."));
    }
}
