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

    // JPQL 프로젝션(new 연산자)이 쓰는 생성자. 시그니처가 쿼리의 컬럼 순서와 일치해야 한다
    public MemoryMarkerResponseDto(Long memoryId, BigDecimal latitude, BigDecimal longitude,
                                   String category, LocalDate memoryDate) {
        this.memoryId = memoryId;
        this.latitude = latitude;
        this.longitude = longitude;
        this.category = category;
        this.memoryDate = memoryDate;
    }
}
