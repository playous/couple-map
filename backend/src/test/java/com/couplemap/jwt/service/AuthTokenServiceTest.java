package com.couplemap.jwt.service;

import com.couplemap.global.exception.exceptions.JwtException;
import com.couplemap.jwt.dto.LoginTokenResponseDto;
import com.couplemap.jwt.util.JWTUtil;
import com.couplemap.jwt.dto.TokenResponseDto;
import com.couplemap.jwt.entity.RefreshToken;
import com.couplemap.jwt.repository.RefreshTokenRepository;
import com.couplemap.jwt.util.TokenExtractor;
import com.couplemap.user.domain.UserRole;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.Optional;

import static com.couplemap.global.exception.code.JwtErrorCode.*;
import static org.assertj.core.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.BDDMockito.*;

@ExtendWith(MockitoExtension.class)
class AuthTokenServiceTest {

    @Mock
    private JWTUtil jwtUtil;

    @Mock
    private TokenExtractor tokenExtractor;

    @Mock
    private RefreshTokenRepository refreshTokenRepository;

    @InjectMocks
    private AuthTokenServiceImpl authTokenService;

    private static final Long ACCESS_TOKEN_EXPIRATION = 1000 * 60 * 30L; // 30분
    private static final Long REFRESH_TOKEN_EXPIRATION = 1000 * 60 * 60 * 24 * 30L; // 30일

    private Long userId;
    private String username;
    private String role;
    private String accessToken;
    private String refreshToken;

    @BeforeEach
    void setUp() {
        ReflectionTestUtils.setField(authTokenService, "ACCESS_TOKEN_EXPIRATION", ACCESS_TOKEN_EXPIRATION);
        ReflectionTestUtils.setField(authTokenService, "REFRESH_TOKEN_EXPIRATION", REFRESH_TOKEN_EXPIRATION);
        
        userId = 1L;
        username = "test@test.com";
        role = "USER";
        accessToken = "access-token";
        refreshToken = "refresh-token";
    }

    @Test
    @DisplayName("토큰 생성 성공")
    void generateTokens_Success() {
        boolean isNicknameSet = false;

        // given
        given(jwtUtil.createJwt("access", username, role, userId, ACCESS_TOKEN_EXPIRATION))
                .willReturn(accessToken);
        given(jwtUtil.createJwt("refresh", username, role, userId, REFRESH_TOKEN_EXPIRATION))
                .willReturn(refreshToken);

        // when
        LoginTokenResponseDto result = authTokenService.generateTokens(userId, username, role, isNicknameSet);

        // then
        assertThat(result).isNotNull();
        assertThat(result.getAccessToken()).isEqualTo(accessToken);
        assertThat(result.getRefreshToken()).isEqualTo(refreshToken);
        assertThat(result.getExpiresIn()).isEqualTo(ACCESS_TOKEN_EXPIRATION / 1000);
        assertThat(result.isNicknameSet()).isEqualTo(isNicknameSet);
        
        then(refreshTokenRepository).should().save(any(RefreshToken.class));
    }

    @Test
    @DisplayName("토큰 재발급 성공 - Refresh Token 재사용")
    void refreshTokens_Success() {
        // given
        String authHeader = "Bearer " + refreshToken;
        String newAccessToken = "new-access-token";
        
        RefreshToken storedToken = RefreshToken.of(userId, refreshToken, REFRESH_TOKEN_EXPIRATION);

        given(tokenExtractor.extractToken(authHeader)).willReturn(refreshToken);
        given(jwtUtil.getCategory(refreshToken)).willReturn("refresh");
        given(jwtUtil.isExpired(refreshToken)).willReturn(false);
        given(jwtUtil.getUserId(refreshToken)).willReturn(userId);
        given(jwtUtil.getUsername(refreshToken)).willReturn(username);
        given(jwtUtil.getRole(refreshToken)).willReturn(UserRole.USER);
        given(refreshTokenRepository.findById(String.valueOf(userId))).willReturn(Optional.of(storedToken));
        given(jwtUtil.createJwt("access", username, role, userId, ACCESS_TOKEN_EXPIRATION))
                .willReturn(newAccessToken);

        // when
        TokenResponseDto result = authTokenService.refreshTokens(authHeader);

        // then
        assertThat(result).isNotNull();
        assertThat(result.getAccessToken()).isEqualTo(newAccessToken);
        assertThat(result.getRefreshToken()).isEqualTo(refreshToken); // 기존 Refresh Token 재사용
        assertThat(result.getExpiresIn()).isEqualTo(ACCESS_TOKEN_EXPIRATION / 1000);
        
        // Refresh Token은 재발급하지 않으므로 save 호출 안 됨
        then(refreshTokenRepository).should(never()).save(any(RefreshToken.class));
    }

    @Test
    @DisplayName("토큰 재발급 실패 - 잘못된 토큰 타입 (Access Token 사용)")
    void refreshTokens_Fail_InvalidTokenType() {
        // given
        String authHeader = "Bearer " + accessToken;
        
        given(tokenExtractor.extractToken(authHeader)).willReturn(accessToken);
        given(jwtUtil.getCategory(accessToken)).willReturn("access"); // Access Token!

        // when & then
        assertThatThrownBy(() -> authTokenService.refreshTokens(authHeader))
                .isInstanceOf(JwtException.class)
                .hasFieldOrPropertyWithValue("code", JWT_INVALID_TOKEN_TYPE);
        
        then(refreshTokenRepository).should(never()).findById(anyString());
    }

    @Test
    @DisplayName("토큰 재발급 실패 - Refresh Token 만료")
    void refreshTokens_Fail_TokenExpired() {
        // given
        String authHeader = "Bearer " + refreshToken;
        
        given(tokenExtractor.extractToken(authHeader)).willReturn(refreshToken);
        given(jwtUtil.isExpired(refreshToken)).willReturn(true); // 만료됨!

        // when & then
        assertThatThrownBy(() -> authTokenService.refreshTokens(authHeader))
                .isInstanceOf(JwtException.class)
                .hasFieldOrPropertyWithValue("code", JWT_REFRESH_TOKEN_EXPIRED);
        
        then(refreshTokenRepository).should(never()).findById(anyString());
    }

    @Test
    @DisplayName("토큰 재발급 실패 - 로그아웃된 토큰 (Redis에 없음)")
    void refreshTokens_Fail_TokenBlacklisted() {
        // given
        String authHeader = "Bearer " + refreshToken;
        
        given(tokenExtractor.extractToken(authHeader)).willReturn(refreshToken);
        given(jwtUtil.getCategory(refreshToken)).willReturn("refresh");
        given(jwtUtil.isExpired(refreshToken)).willReturn(false);
        given(jwtUtil.getUserId(refreshToken)).willReturn(userId);
        given(refreshTokenRepository.findById(String.valueOf(userId))).willReturn(Optional.empty());

        // when & then
        assertThatThrownBy(() -> authTokenService.refreshTokens(authHeader))
                .isInstanceOf(JwtException.class)
                .hasFieldOrPropertyWithValue("code", JWT_TOKEN_BLACKLISTED);
    }

    @Test
    @DisplayName("로그아웃 성공")
    void logout_Success() {
        // given & when
        authTokenService.logout(userId);

        // then
        then(refreshTokenRepository).should().deleteById(String.valueOf(userId));
    }

    @Test
    @DisplayName("로그아웃 후 토큰 재사용 불가")
    void afterLogout_CannotReuseToken() {
        // given
        String authHeader = "Bearer " + refreshToken;

        // 로그아웃
        authTokenService.logout(userId);

        // 로그아웃 후 토큰 재발급 시도
        given(tokenExtractor.extractToken(authHeader)).willReturn(refreshToken);
        given(jwtUtil.getCategory(refreshToken)).willReturn("refresh");
        given(jwtUtil.isExpired(refreshToken)).willReturn(false);
        given(jwtUtil.getUserId(refreshToken)).willReturn(userId);
        given(refreshTokenRepository.findById(String.valueOf(userId))).willReturn(Optional.empty());

        // when & then
        assertThatThrownBy(() -> authTokenService.refreshTokens(authHeader))
                .isInstanceOf(JwtException.class)
                .hasFieldOrPropertyWithValue("code", JWT_TOKEN_BLACKLISTED);
    }

    @Test
    @DisplayName("여러 번 Access Token 재발급 가능 (Refresh Token 재사용)")
    void canRefreshMultipleTimes() {
        // given
        String authHeader = "Bearer " + refreshToken;
        RefreshToken storedToken = RefreshToken.of(userId, refreshToken, REFRESH_TOKEN_EXPIRATION);

        given(tokenExtractor.extractToken(authHeader)).willReturn(refreshToken);
        given(jwtUtil.getCategory(refreshToken)).willReturn("refresh");
        given(jwtUtil.isExpired(refreshToken)).willReturn(false);
        given(jwtUtil.getUserId(refreshToken)).willReturn(userId);
        given(jwtUtil.getUsername(refreshToken)).willReturn(username);
        given(jwtUtil.getRole(refreshToken)).willReturn(UserRole.USER);
        given(refreshTokenRepository.findById(String.valueOf(userId))).willReturn(Optional.of(storedToken));
        
        given(jwtUtil.createJwt(eq("access"), eq(username), eq(role), eq(userId), eq(ACCESS_TOKEN_EXPIRATION)))
                .willReturn("access-token-1", "access-token-2", "access-token-3");

        // when
        TokenResponseDto result1 = authTokenService.refreshTokens(authHeader);
        TokenResponseDto result2 = authTokenService.refreshTokens(authHeader);
        TokenResponseDto result3 = authTokenService.refreshTokens(authHeader);

        // then
        assertThat(result1.getAccessToken()).isEqualTo("access-token-1");
        assertThat(result2.getAccessToken()).isEqualTo("access-token-2");
        assertThat(result3.getAccessToken()).isEqualTo("access-token-3");
        
        // Refresh Token은 계속 동일
        assertThat(result1.getRefreshToken()).isEqualTo(refreshToken);
        assertThat(result2.getRefreshToken()).isEqualTo(refreshToken);
        assertThat(result3.getRefreshToken()).isEqualTo(refreshToken);
        
        // 저장은 한 번도 호출되지 않음 (Refresh Token 재사용)
        then(refreshTokenRepository).should(never()).save(any(RefreshToken.class));
    }
}
