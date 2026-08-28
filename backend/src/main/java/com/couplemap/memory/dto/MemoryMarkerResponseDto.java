package com.couplemap.memory.dto;

import com.couplemap.memory.domain.Memory;
import lombok.Getter;

import java.math.BigDecimal;
import java.time.LocalDate;

@Getter
public class MemoryMarkerResponseDto {
    private final Long memoryId;
    private final BigDecimal latitude;
    private final BigDecimal longitude;
    private final String category;
    private final LocalDate memoryDate;

    public MemoryMarkerResponseDto(Memory memory) {
        this.memoryId = memory.getMemoryId();
        this.latitude = memory.getLatitude();
        this.longitude = memory.getLongitude();
        this.category = memory.getCategory();
        this.memoryDate = memory.getMemoryDate();
    }
}
