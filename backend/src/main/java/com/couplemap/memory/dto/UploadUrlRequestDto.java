package com.couplemap.memory.dto;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import lombok.AllArgsConstructor;
import lombok.Getter;
import lombok.NoArgsConstructor;

import java.util.List;

@Getter
@NoArgsConstructor
@AllArgsConstructor
public class UploadUrlRequestDto {

    @Valid
    @NotEmpty(message = "업로드할 파일 정보가 필요합니다.")
    @Size(max = 10, message = "한 번에 최대 10개까지 업로드할 수 있습니다.")
    private List<FileSpec> files;

    @Getter
    @NoArgsConstructor
    @AllArgsConstructor
    public static class FileSpec {

        @NotBlank(message = "파일명은 필수입니다.")
        private String filename;

        @NotBlank(message = "파일 형식은 필수입니다.")
        private String contentType;

        @NotNull(message = "파일 크기는 필수입니다.")
        private Long size;
    }
}
