package com.couplemap.global.upload;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import lombok.AllArgsConstructor;
import lombok.Getter;
import lombok.NoArgsConstructor;

@Getter
@NoArgsConstructor
@AllArgsConstructor
public class ImageUploadRequestDto {

    @NotBlank(message = "파일명은 필수입니다.")
    private String filename;

    @NotBlank(message = "파일 형식은 필수입니다.")
    private String contentType;

    @NotNull(message = "파일 크기는 필수입니다.")
    private Long size;
}
