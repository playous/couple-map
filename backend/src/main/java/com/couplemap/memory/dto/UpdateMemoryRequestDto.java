package com.couplemap.memory.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import lombok.AllArgsConstructor;
import lombok.Getter;
import lombok.NoArgsConstructor;

import java.time.LocalDate;
import java.util.List;

@Getter
@NoArgsConstructor
@AllArgsConstructor
public class UpdateMemoryRequestDto {

    @NotBlank(message = "제목은 필수입니다.")
    @Size(max = 50, message = "제목은 최대 50자까지 입력 가능합니다.")
    private String title;

    @Size(max = 100, message = "내용은 최대 100자까지 입력 가능합니다.")
    private String content;

    @NotBlank(message = "장소명은 필수입니다.")
    private String placeName;

    @NotNull(message = "추억 날짜는 필수입니다.")
    private LocalDate memoryDate;

    private String category;

    // 삭제할 기존 파일의 ID 목록
    private List<Long> deleteFileIds;

    // 파일을 추가할 때만 채운다. /uploads로 발급받아 S3에 올린 뒤 전달
    private String uploadId;
    private List<CompleteUploadRequestDto.FileRef> files;
}
