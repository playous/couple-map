package com.couplemap.memory.dto;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import lombok.AllArgsConstructor;
import lombok.Getter;
import lombok.NoArgsConstructor;

import java.util.List;

@Getter
@NoArgsConstructor
@AllArgsConstructor
public class CompleteUploadRequestDto {

    @NotBlank(message = "uploadId는 필수입니다.")
    private String uploadId;

    @Valid
    @NotNull(message = "추억 정보는 필수입니다.")
    private CreateMemoryRequestDto request;

    @Valid
    private List<FileRef> files;

    @Getter
    @NoArgsConstructor
    @AllArgsConstructor
    public static class FileRef {

        @NotBlank(message = "fileKey는 필수입니다.")
        private String fileKey;

        @NotNull(message = "displayOrder는 필수입니다.")
        private Integer displayOrder;
    }
}
