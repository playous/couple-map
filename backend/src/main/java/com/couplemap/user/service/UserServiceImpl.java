package com.couplemap.user.service;

import com.couplemap.friend.repository.FriendshipRepository;
import com.couplemap.global.exception.exceptions.UserException;
import com.couplemap.global.filecleanup.FileCleanupService;
import com.couplemap.global.s3.S3Service;
import com.couplemap.global.upload.ImageUploadService;
import com.couplemap.jwt.repository.RefreshTokenRepository;
import com.couplemap.map.domain.Map;
import com.couplemap.map.repository.MapMemberRepository;
import com.couplemap.map.repository.MapRepository;
import com.couplemap.mediafile.repository.MediaFileRepository;
import com.couplemap.user.domain.User;
import com.couplemap.user.dto.ProfileImageRequestDto;
import com.couplemap.user.dto.ProfileImageResponseDto;
import com.couplemap.user.dto.NicknameResponseDto;
import com.couplemap.user.dto.UserInfoResponseDto;
import com.couplemap.memory.repository.MemoryRepository;
import com.couplemap.user.repository.UserRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;

import java.util.*;

import static com.couplemap.global.exception.code.UserErrorCode.DUPLICATE_NICKNAME;
import static com.couplemap.global.exception.code.UserErrorCode.USER_NOT_FOUND;
import static com.couplemap.map.domain.MapMemberRole.EDITOR;
import static com.couplemap.map.domain.MapMemberRole.OWNER;

@Slf4j
@Service
@RequiredArgsConstructor
@Transactional(readOnly = true)
public class UserServiceImpl implements UserService {

    private final UserRepository userRepository;
    private final MemoryRepository memoryRepository;
    private final FriendshipRepository friendshipRepository;
    private final MapMemberRepository mapMemberRepository;
    private final MapRepository mapRepository;
    private final RefreshTokenRepository refreshTokenRepository;
    private final S3Service s3Service;
    private final FileCleanupService fileCleanupService;
    private final MediaFileRepository mediaFileRepository;
    private final ImageUploadService imageUploadService;

    @Transactional
    public ProfileImageResponseDto updateProfileImage(Long userId, ProfileImageRequestDto request) {

        User user = userRepository.findById(userId)
                .orElseThrow(() -> new UserException(USER_NOT_FOUND));

        String fileKey = imageUploadService.consume(request.getUploadId(), request.getFileKey(), userId);

        String oldProfileImageKey = user.getProfileImageKey();
        if (oldProfileImageKey != null) {
            fileCleanupService.scheduleDelete(oldProfileImageKey);
        }

        user.updateProfileImageKey(fileKey);

        return ProfileImageResponseDto.builder()
                .imageUrl(s3Service.getFileUrl(fileKey))
                .build();
    }

    @Transactional
    public void deleteProfileImage(Long userId) {
        User user = userRepository.findById(userId)
                .orElseThrow(() -> new UserException(USER_NOT_FOUND));
        if (user.getProfileImageKey() == null) {
            return;
        }
        fileCleanupService.scheduleDelete(user.getProfileImageKey());

        user.deleteProfileImage();
    }

    @Transactional
    public NicknameResponseDto setNickname(Long userId, String nickname) {
        User user = userRepository.findById(userId)
                .orElseThrow(() -> new UserException(USER_NOT_FOUND));

        Optional<User> existingUser = userRepository.findByNickname(nickname);

        if (existingUser.isPresent() && !existingUser.get().getUserId().equals(userId)) {
            throw new UserException(DUPLICATE_NICKNAME);
        }
        
        user.updateNickname(nickname);
        
        return NicknameResponseDto.builder()
                .nickname(nickname)
                .build();
    }

    public UserInfoResponseDto getUserInfo(Long userId) {
        User user = userRepository.findById(userId)
                .orElseThrow(() -> new UserException(USER_NOT_FOUND));

        long memoryCount = memoryRepository.countByUserMaps(userId, List.of(OWNER, EDITOR));
        return UserInfoResponseDto.from(user, memoryCount, s3Service::getFileUrl);
    }

    @Transactional
    public void deleteAccount(Long userId) {
        User user = userRepository.findById(userId)
                .orElseThrow(() -> new UserException(USER_NOT_FOUND));

        // S3 삭제 예약할 파일 키 수집
        Set<String> fileKeysToDelete = new HashSet<>(mediaFileRepository.findFileKeysByUserId(userId));

        // 1. 유저가 작성한 미디어 파일 DB 삭제
        mediaFileRepository.deleteAllByUserId(userId);

        // 2. 유저가 작성한 추억 삭제
        memoryRepository.deleteAllByUser_UserId(userId);

        // 3. OWNER인 지도 → 해당 지도의 추억, 멤버, 지도 삭제
        List<Map> ownedMaps = mapMemberRepository.findOwnedMapsByUserId(userId, OWNER);
        for (Map map : ownedMaps) {
            fileKeysToDelete.addAll(mediaFileRepository.findFileKeysByMapId(map.getMapId()));
            mediaFileRepository.deleteAllByMapId(map.getMapId());
            memoryRepository.deleteAllByMap_MapId(map.getMapId());
            mapMemberRepository.deleteAllByMap(map);
            if (map.getBackgroundKey() != null) {
                fileKeysToDelete.add(map.getBackgroundKey());
            }
            mapRepository.delete(map);
        }

        // 4. 참여 중인 지도 멤버 삭제
        mapMemberRepository.deleteAllByUserId(userId);

        // 5. 남의 지도에 남긴 초대자 참조 끊기 — 없으면 8번에서 FK 위반으로 탈퇴가 영구 실패
        mapMemberRepository.clearInviterByUserId(userId);

        // 6. 친구 관계 삭제
        friendshipRepository.deleteAllByUserId(userId);

        // 7. 프로필 이미지 + S3 파일 삭제 일괄 예약
        if (user.getProfileImageKey() != null) {
            fileKeysToDelete.add(user.getProfileImageKey());
        }
        fileCleanupService.scheduleDeleteAll(new ArrayList<>(fileKeysToDelete));

        // 8. 유저 삭제
        userRepository.delete(user);

        // 9. 리프레시 토큰 삭제 — 반드시 커밋이 확정된 뒤에
        deleteRefreshTokenAfterCommit(userId);
    }

    // Redis는 롤백이 없으므로 RDB 커밋 확정 후에 지운다 — 실패는 로그만 (계정은 이미 삭제됨, 토큰은 TTL 만료)
    private void deleteRefreshTokenAfterCommit(Long userId) {
        if (!TransactionSynchronizationManager.isSynchronizationActive()) {
            refreshTokenRepository.deleteById(String.valueOf(userId));
            return;
        }
        TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
            @Override
            public void afterCommit() {
                try {
                    refreshTokenRepository.deleteById(String.valueOf(userId));
                } catch (Exception e) {
                    log.error("[userId : {}] 탈퇴 후 리프레시 토큰 삭제 실패 — TTL 만료까지 잔존", userId, e);
                }
            }
        });
    }
}
