package com.couplemap.friend.domain;

import com.couplemap.global.common.BaseEntity;
import com.couplemap.global.exception.exceptions.FriendException;
import com.couplemap.user.domain.User;
import jakarta.persistence.*;
import lombok.*;

import static com.couplemap.friend.domain.FriendshipStatus.*;
import static com.couplemap.global.exception.code.FriendErrorCode.FRIEND_REQUEST_ALREADY_RESOLVED;
import static com.couplemap.global.exception.code.FriendErrorCode.NOT_MATCH_RECEIVER;

@Getter
@Entity
@Table(name = "friendships", uniqueConstraints = @UniqueConstraint(name = "uk_friendships_friend_pair_key", columnNames = "friend_pair_key"))
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@Builder(access = AccessLevel.PRIVATE)
@AllArgsConstructor
public class Friendship extends BaseEntity {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "friendship_id")
    private Long friendshipId;

    // 친구 요청 보낸 사람
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "requester_id", nullable = false, foreignKey = @ForeignKey(name = "fk_friendships_requester"))
    private User requester;

    // 친구 요청 받은 사람
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "receiver_id", nullable = false, foreignKey = @ForeignKey(name = "fk_friendships_receiver"))
    private User receiver;

    @Enumerated(EnumType.STRING)
    @Column(name = "status", nullable = false, length = 20)
    private FriendshipStatus status;

    @Column(name = "friend_pair_key", nullable = false, length = 50)
    private String friendPairKey;

    public static Friendship createRequest(User requester, User receiver) {
        return Friendship.builder()
                .requester(requester)
                .receiver(receiver)
                .status(PENDING)
                .friendPairKey(createPairKey(requester, receiver))
                .build();
    }

    public void accept(Long userId) {
        validateReceiver(userId);      // 검증 1
        validatePendingStatus();       // 검증 2
        this.status = ACCEPTED;        // 수락 처리
    }

    public void reject(Long userId) {
        validateReceiver(userId);      // 검증 1
        validatePendingStatus();       // 검증 2
        this.status = REJECTED;        // 거절 처리
    }

    /*
    요청 받은 사람이 본인이 아닌 경우
     */
    private void validateReceiver(Long userId) {
        if (!this.receiver.getUserId().equals(userId)) {
            throw new FriendException(NOT_MATCH_RECEIVER);
        }
    }

    /*
    이미 처리된 요청인경우
     */
    private void validatePendingStatus() {
        if (this.status == ACCEPTED || this.status == REJECTED) {
            throw new FriendException(FRIEND_REQUEST_ALREADY_RESOLVED);
        }
    }

    private static String createPairKey(User requester, User receiver) {
        Long requesterId = requester.getUserId();
        Long receiverId = receiver.getUserId();

        long smallerId = Math.min(requesterId, receiverId);
        long largerId = Math.max(requesterId, receiverId);

        return smallerId + ":" + largerId;
    }
}
