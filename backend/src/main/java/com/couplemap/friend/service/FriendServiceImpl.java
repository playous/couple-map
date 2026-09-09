package com.couplemap.friend.service;

import com.couplemap.friend.domain.Friendship;
import com.couplemap.friend.dto.FriendListResponseDto;
import com.couplemap.friend.dto.FriendPendingListResponseDto;
import com.couplemap.friend.dto.FriendRequestResponseDto;
import com.couplemap.friend.dto.SendFriendRequestDto;
import com.couplemap.friend.repository.FriendshipRepository;
import com.couplemap.global.exception.exceptions.FriendException;
import com.couplemap.global.exception.exceptions.UserException;
import com.couplemap.global.s3.S3Service;
import com.couplemap.user.domain.User;
import com.couplemap.user.repository.UserRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.ArrayList;
import java.util.List;

import static com.couplemap.friend.domain.FriendshipStatus.ACCEPTED;
import static com.couplemap.friend.domain.FriendshipStatus.PENDING;
import static com.couplemap.global.exception.code.FriendErrorCode.*;
import static com.couplemap.global.exception.code.UserErrorCode.USER_NOT_FOUND;

@Service
@RequiredArgsConstructor
@Transactional(readOnly = true)
public class FriendServiceImpl implements FriendService {

    private final FriendshipRepository friendshipRepository;
    private final UserRepository userRepository;
    private final S3Service s3Service;

    @Transactional
    public FriendRequestResponseDto sendFriendRequest(SendFriendRequestDto sendFriendRequestDto, Long requesterId) {

        String code = sendFriendRequestDto.getFriendCode();

        User requester = userRepository.findById(requesterId)
                .orElseThrow(() -> new UserException(USER_NOT_FOUND));

        User receiver = userRepository.findByFriendCode(code)
                .orElseThrow(() -> new FriendException(INVALID_FRIEND_CODE));

        validateFriendRequest(requester, receiver);

        Friendship friendship = Friendship.createRequest(requester, receiver);

        try {
            friendshipRepository.save(friendship);
            friendshipRepository.flush();
        } catch (DataIntegrityViolationException e) {
            throw new FriendException(FRIEND_REQUEST_CONFLICT);
        }

        return FriendRequestResponseDto.from(friendship);
    }

    public FriendListResponseDto getFriendList(Long userId) {
        List<User> friendList = new ArrayList<>();
        friendList.addAll(friendshipRepository.findFriendsWhereReceiver(userId, ACCEPTED));
        friendList.addAll(friendshipRepository.findFriendsWhereRequester(userId, ACCEPTED));

        return FriendListResponseDto.from(friendList, s3Service::getFileUrl);
    }

    public FriendPendingListResponseDto getFriendPendingList(Long userId) {
        List<Friendship> friendList = new ArrayList<>();
        friendList.addAll(friendshipRepository.findFriendshipsWhereReceiver(userId, PENDING));
        return FriendPendingListResponseDto.from(friendList, s3Service::getFileUrl);
    }


    @Transactional
    public void reject(Long friendshipId, Long receiverId) {
        Friendship friendship = getFriendshipOrThrow(friendshipId);

        friendship.reject(receiverId);

        friendshipRepository.save(friendship);
    }

    @Transactional
    public void accept (Long friendshipId, Long receiverId) {
        Friendship friendship = getFriendshipOrThrow(friendshipId);

        friendship.accept(receiverId);

        friendshipRepository.save(friendship);
    }

    private void validateFriendRequest(User requester, User receiver) {
        if (requester.getUserId().equals(receiver.getUserId())) {
            throw new FriendException(CANNOT_FRIEND_YOURSELF);
        }

        if (friendshipRepository.existsFriendship(requester, receiver, ACCEPTED)) {
            throw new FriendException(FRIEND_ALREADY_EXISTS);
        }

        if (friendshipRepository.existsFriendship(requester, receiver, PENDING)) {
            throw new FriendException(FRIEND_PENDING_EXISTS);
        }
    }

    private Friendship getFriendshipOrThrow(Long friendshipId) {
        return friendshipRepository.findById(friendshipId)
                .orElseThrow(() -> new FriendException(INVALID_FRIENDSHIP_ID));
    }
}
