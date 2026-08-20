package com.couplemap.jwt.service;

import com.couplemap.global.exception.exceptions.JwtException;
import com.couplemap.jwt.dto.LoginTokenResponseDto;
import com.couplemap.jwt.util.JWTUtil;
import com.couplemap.jwt.dto.TokenResponseDto;
import com.couplemap.jwt.entity.RefreshToken;
import com.couplemap.jwt.repository.RefreshTokenRepository;
import com.couplemap.jwt.util.TokenExtractor;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import static com.couplemap.global.exception.code.JwtErrorCode.*;

@Service
@Slf4j
@RequiredArgsConstructor
public class AuthTokenServiceImpl implements AuthTokenService {

    private final JWTUtil jwtUtil;
    private final TokenExtractor tokenExtractor;
    private final RefreshTokenRepository refreshTokenRepository;

    @Value("${spring.jwt.access-token.expiration}")
    private Long ACCESS_TOKEN_EXPIRATION;

    @Value("${spring.jwt.refresh-token.expiration}")
    private Long REFRESH_TOKEN_EXPIRATION;

    /**
     * 토큰 생성 및 저장 (최초 로그인 시)
     */
    public LoginTokenResponseDto generateTokens(Long userId, String username, String role, boolean isNicknameSet) {

        String accessToken = jwtUtil.createJwt("access", username, role, userId, ACCESS_TOKEN_EXPIRATION);
        String refreshToken = jwtUtil.createJwt("refresh", username, role, userId, REFRESH_TOKEN_EXPIRATION);

        RefreshToken token = RefreshToken.of(userId, refreshToken, REFRESH_TOKEN_EXPIRATION);
        refreshTokenRepository.save(token);

        log.debug("[userId : {}] 토큰 생성 완료", userId);

        return LoginTokenResponseDto.builder()
                .accessToken(accessToken)
                .refreshToken(refreshToken)
                .expiresIn(ACCESS_TOKEN_EXPIRATION / 1000)
                .isNicknameSet(isNicknameSet)
                .build();
    }

    /**
     * Access Token 재발급 (Refresh Token은 재사용)
     */
    public TokenResponseDto refreshTokens(String authHeader) {

        String refreshToken = tokenExtractor.extractToken(authHeader);

        validateRefreshToken(refreshToken);

        Long userId = jwtUtil.getUserId(refreshToken);
        String username = jwtUtil.getUsername(refreshToken);
        String role = jwtUtil.getRole(refreshToken).name();

        String accessToken = jwtUtil.createJwt("access", username, role, userId, ACCESS_TOKEN_EXPIRATION);

        log.debug("[userId : {}] Access Token 재발급 완료", userId);

        return TokenResponseDto.builder()
                .accessToken(accessToken)
                .refreshToken(refreshToken)
                .expiresIn(ACCESS_TOKEN_EXPIRATION / 1000)
                .build();
    }

    /**
     * 로그아웃
     */
    public void logout(Long userId) {

        refreshTokenRepository.deleteById(String.valueOf(userId));

        log.debug("[userId : {}] 로그아웃 완료", userId);
    }


    private void validateRefreshToken(String refreshToken) {
        // 만료 시간 확인
        if (jwtUtil.isExpired(refreshToken)) {
            throw new JwtException(JWT_REFRESH_TOKEN_EXPIRED);
        }

        // 카테고리 확인
        String category = jwtUtil.getCategory(refreshToken);
        if (!"refresh".equals(category)) {
            throw new JwtException(JWT_INVALID_TOKEN_TYPE);
        }

        // 로그아웃한 사용자인지 확인
        Long userId = jwtUtil.getUserId(refreshToken);
        RefreshToken storedToken = refreshTokenRepository.findById(String.valueOf(userId))
                .orElseThrow(() -> new JwtException(JWT_TOKEN_BLACKLISTED));
        if (!storedToken.getRefreshToken().equals(refreshToken)) {
            throw new JwtException(JWT_TOKEN_BLACKLISTED);
        }
    }
}
