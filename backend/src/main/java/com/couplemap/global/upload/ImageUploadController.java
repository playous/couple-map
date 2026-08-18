package com.couplemap.global.upload;

import com.couplemap.global.response.ApiResponse;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@Tag(name = "Upload", description = "이미지 업로드 URL 발급 API")
@RestController
@RequestMapping("/api/uploads")
@RequiredArgsConstructor
public class ImageUploadController {

    private final ImageUploadService imageUploadService;

    @Operation(summary = "이미지 업로드 URL 발급", description = "프로필 이미지·지도 배경을 S3에 직접 업로드할 URL을 발급합니다.")
    @PostMapping("/image")
    public ResponseEntity<ApiResponse<ImageUploadResponseDto>> issueImageUploadUrl(
            @Valid @RequestBody ImageUploadRequestDto request,
            @AuthenticationPrincipal(expression = "userId") Long userId) {
        ImageUploadResponseDto response = imageUploadService.issue(request, userId);
        return ResponseEntity.ok(ApiResponse.success(response, "업로드 URL이 발급되었습니다."));
    }
}
