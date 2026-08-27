package com.couplemap.user.domain;

import com.couplemap.global.common.BaseEntity;
import jakarta.persistence.*;
import lombok.AccessLevel;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;

@Entity
@Getter
@Table(name = "users", uniqueConstraints = {
        @UniqueConstraint(name = "uk_users_nickname", columnNames = "nickname"),
        @UniqueConstraint(name = "uk_users_provider_id", columnNames = "provider_id"),
        @UniqueConstraint(name = "uk_users_friend_code", columnNames = "friend_code")
})
@NoArgsConstructor(access = AccessLevel.PROTECTED)
public class User extends BaseEntity {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "user_id")
    private Long userId;

    @Enumerated(EnumType.STRING)
    @Column(name = "role", nullable = false)
    private UserRole role;

    @Column(name = "email", nullable = false, length = 100)
    private String email;

    @Column(name = "name", nullable = false, length = 50)
    private String name;

    // 닉네임 (회원가입 후 입력)
    @Column(name = "nickname", length = 10)
    private String nickname;

    // 접근, 삭제 모두 이 키로 한다. URL은 조회 시점에 서명해서 만들고 저장하지 않는다
    @Column(name = "profile_image_key", length = 200)
    private String profileImageKey;

    @Column(name = "login_type", nullable = false)
    private String loginType;  // GOOGLE, NAVER, KAKAO

    // OAuth 제공 ID
    @Column(name = "provider_id", nullable = false, length = 200)
    private String providerId;

    @Column(name = "friend_code", nullable = false)
    private String friendCode;

    @Builder
    public User(String loginType, String providerId, String email, String name, UserRole role, String friendCode) {
        this.loginType = loginType;
        this.providerId = providerId;
        this.email = email;
        this.name = name;
        this.role = role;
        this.friendCode = friendCode;
    }

    public void updateProfileImageKey(String fileKey) {
        this.profileImageKey = fileKey;
    }

    public void updateProfile(String name, String email) {
        this.name = name;
        this.email = email;
    }

    public void deleteProfileImage() {
        this.profileImageKey = null;
    }

    public void updateNickname(String nickname) {
        this.nickname = nickname;
    }

    public boolean hasNickname() {
        return this.nickname != null && !this.nickname.isBlank();
    }
}