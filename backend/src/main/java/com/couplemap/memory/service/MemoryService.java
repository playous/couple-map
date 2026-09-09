package com.couplemap.memory.service;

import com.couplemap.memory.dto.CalendarMemoryResponseDto;
import com.couplemap.memory.dto.CompleteUploadRequestDto;
import com.couplemap.memory.dto.CreateMemoryRequestDto;
import com.couplemap.memory.dto.MemoryDetailResponseDto;
import com.couplemap.memory.dto.MemoryListResponseDto;
import com.couplemap.memory.dto.MemoryMarkerResponseDto;
import com.couplemap.memory.dto.UpdateMemoryRequestDto;
import com.couplemap.memory.dto.UploadUrlRequestDto;
import com.couplemap.memory.dto.UploadUrlResponseDto;
import org.springframework.data.domain.Pageable;
import org.springframework.data.domain.Slice;

import java.util.List;

public interface MemoryService {
    Long createMemory(Long mapId, CreateMemoryRequestDto request, Long userId);
    Slice<MemoryListResponseDto> getMemoryList(Long mapId, Long userId, Pageable pageable);
    List<MemoryMarkerResponseDto> getMemoryMarkers(Long mapId, Long userId);
    MemoryDetailResponseDto getMemoryDetail(Long mapId, Long memoryId, Long userId);
    void deleteMemory(Long mapId, Long memoryId, Long userId);
    Long updateMemory(Long mapId, Long memoryId, UpdateMemoryRequestDto request, Long userId);
    List<CalendarMemoryResponseDto> getCalendarMemories(int year, Integer month, Long userId);
    UploadUrlResponseDto issueUploadUrls(Long mapId, UploadUrlRequestDto request, Long userId);
    Long completeUpload(Long mapId, CompleteUploadRequestDto request, Long userId);
}
