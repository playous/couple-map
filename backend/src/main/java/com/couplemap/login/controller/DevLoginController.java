package com.couplemap.login.controller;

import com.couplemap.global.response.ApiResponse;
import com.couplemap.jwt.dto.LoginTokenResponseDto;
import com.couplemap.jwt.service.AuthTokenService;
import com.couplemap.user.domain.User;
import com.couplemap.user.repository.UserRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.context.annotation.Profile;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;


@Profile("dev")
@RestController
@RequiredArgsConstructor
@RequestMapping("/api/dev")
public class DevLoginController {

    private final UserRepository userRepository;
    private final AuthTokenService authTokenService;

    @PostMapping("/login/{providerId}")
    public ResponseEntity<ApiResponse<LoginTokenResponseDto>> devLogin(@PathVariable String providerId) {

        User user = userRepository.findByProviderId(providerId);

        if (user == null) throw new RuntimeException("테스트 유저 없음: " + providerId);

        LoginTokenResponseDto tokens = authTokenService.generateTokens(
                user.getUserId(),
                user.getEmail(),
                user.getRole().name(),
                user.hasNickname()
        );

        return ResponseEntity.ok(ApiResponse.success(tokens, "개발용 로그인 완료"));
    }
}
