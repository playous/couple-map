package com.couplemap.map.domain;

import com.couplemap.global.common.BaseEntity;
import com.couplemap.user.domain.User;
import jakarta.persistence.*;
import lombok.AccessLevel;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;

@Entity
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@Table(name = "map_members", uniqueConstraints = @UniqueConstraint(name = "uk_map_members_map_user", columnNames = {"map_id", "user_id"}))
public class MapMember extends BaseEntity {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "map_member_id")
    private Long mapMemberId;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "map_id", nullable = false, foreignKey = @ForeignKey(name = "fk_map_members_map"))
    private Map map;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "user_id", nullable = false, foreignKey = @ForeignKey(name = "fk_map_members_user"))
    private User user;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "inviter_id", foreignKey = @ForeignKey(name = "fk_map_members_inviter"))
    private User inviter;

    @Enumerated(EnumType.STRING)
    @Column(name = "map_member_role", nullable = false, length = 20)
    private MapMemberRole mapMemberRole;

    @Builder
    private MapMember(Map map, User user, User inviter, MapMemberRole mapMemberRole) {
        this.map = map;
        this.user = user;
        this.inviter = inviter;
        this.mapMemberRole = mapMemberRole;
    }

    public static MapMember from(Map map, User user, MapMemberRole role) {
        return MapMember.builder()
                .map(map)
                .user(user)
                .mapMemberRole(role)
                .build();
    }

    public static MapMember from(Map map, User user, User inviter, MapMemberRole role) {
        return MapMember.builder()
                .map(map)
                .user(user)
                .inviter(inviter)
                .mapMemberRole(role)
                .build();
    }

    public void accept() {
        this.mapMemberRole = MapMemberRole.EDITOR;
    }

    public boolean isPending() {
        return this.mapMemberRole == MapMemberRole.PENDING;
    }

    public boolean isInvitedUser(User user) {
        return this.user.equals(user);
    }
}
