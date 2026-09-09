package com.couplemap.user.dto;

import jakarta.validation.constraints.NotBlank;
import lombok.AllArgsConstructor;
import lombok.Getter;
import lombok.NoArgsConstructor;

@Getter
@NoArgsConstructor
@AllArgsConstructor
public class ProfileImageRequestDto {

    @NotBlank(message = "uploadId는 필수입니다.")
    private String uploadId;

    @NotBlank(message = "fileKey는 필수입니다.")
    private String fileKey;
}
