package com.couplemap.map.service;

import com.couplemap.friend.domain.FriendshipStatus;
import com.couplemap.friend.repository.FriendshipRepository;
import com.couplemap.global.exception.exceptions.FriendException;
import com.couplemap.global.exception.exceptions.MapException;
import com.couplemap.global.exception.exceptions.UserException;
import com.couplemap.global.filecleanup.FileCleanupService;
import com.couplemap.global.s3.S3Service;
import com.couplemap.global.upload.ImageUploadService;
import com.couplemap.mediafile.repository.MediaFileRepository;
import com.couplemap.memory.repository.MemoryRepository;
import com.couplemap.map.domain.Map;
import com.couplemap.map.domain.MapMember;
import com.couplemap.map.dto.*;
import com.couplemap.map.repository.MapMemberRepository;
import com.couplemap.map.repository.MapRepository;
import com.couplemap.user.domain.User;
import com.couplemap.user.repository.UserRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.HashMap;
import java.util.List;
import java.util.stream.Collectors;

import static com.couplemap.global.exception.code.FriendErrorCode.INVALID_FRIENDSHIP_ID;
import static com.couplemap.global.exception.code.MapErrorCode.*;
import static com.couplemap.global.exception.code.UserErrorCode.USER_NOT_FOUND;
import static com.couplemap.map.domain.MapMemberRole.*;

@Service
@RequiredArgsConstructor
@Transactional(readOnly = true)
public class MapServiceImpl implements MapService {

    private final MapRepository mapRepository;
    private final MapMemberRepository mapMemberRepository;
    private final UserRepository userRepository;
    private final FriendshipRepository friendshipRepository;
    private final S3Service s3Service;
    private final ImageUploadService imageUploadService;
    private final FileCleanupService fileCleanupService;
    private final MemoryRepository memoryRepository;
    private final MediaFileRepository mediaFileRepository;

    @Override
    @Transactional
    public Long createMap(CreateMapRequestDto request, Long userId) {
        User user = userRepository.findById(userId)
                .orElseThrow(() -> new UserException(USER_NOT_FOUND));

        if (mapMemberRepository.existsByUserIdAndMapName(userId, request.getMapName(), PENDING)) {
            throw new MapException(MAP_NAME_DUPLICATED);
        }

        Map newMap = Map.from(request.getMapName(), request.getDescription(), request.getCategory());

        if (request.getBackgroundKey() != null) {
            String fileKey = imageUploadService.consume(
                    request.getUploadId(), request.getBackgroundKey(), userId);
            newMap.updateBackgroundKey(fileKey);
        }

        mapRepository.save(newMap);

        MapMember mapMember = MapMember.from(newMap, user, OWNER);
        mapMemberRepository.save(mapMember);

        return newMap.getMapId();
    }

    @Override
    @Transactional
    public void deleteMap(Long mapId, Long userId) {
        MapMember mapMember = mapMemberRepository.findByMap_MapIdAndUser_UserId(mapId, userId)
                .orElseThrow(() -> new MapException(NOT_MAP_MEMBER));

        if (mapMember.getMapMemberRole() != OWNER) {
            throw new MapException(NO_DELETE_PERMISSION);
        }

        Map dMap = mapMember.getMap();

        // 지도에 속한 추억의 미디어 파일 S3 삭제 예약
        fileCleanupService.scheduleDeleteAll(mediaFileRepository.findFileKeysByMapId(mapId));

        // 미디어 파일 DB 삭제
        mediaFileRepository.deleteAllByMapId(mapId);

        // 추억 삭제
        memoryRepository.deleteAllByMap_MapId(mapId);

        // 배경 이미지 S3 삭제 예약
        if (dMap.getBackgroundKey() != null) {
            fileCleanupService.scheduleDelete(dMap.getBackgroundKey());
        }

        mapMemberRepository.deleteAllByMap(dMap);
        mapRepository.delete(dMap);
    }

    @Override
    @Transactional
    public void updateMap(Long mapId, UpdateMapRequestDto request, Long userId) {
        Map map = mapRepository.findById(mapId)
                .orElseThrow(() -> new MapException(MAP_NOT_FOUND));

        MapMember mapMember = mapMemberRepository.findByMap_MapIdAndUser_UserId(mapId, userId)
                .orElseThrow(() -> new MapException(NOT_MAP_MEMBER));

        if (mapMember.getMapMemberRole() != OWNER) {
            throw new MapException(NO_UPDATE_PERMISSION);
        }

        if (mapMemberRepository.existsByUserIdAndMapNameExcludingMapId(userId, request.getMapName(), mapId, PENDING)) {
            throw new MapException(MAP_NAME_DUPLICATED);
        }

        map.update(request.getMapName(), request.getDescription(), request.getCategory());

        if (request.getBackgroundKey() != null) {
            String oldBackgroundKey = map.getBackgroundKey();
            String fileKey = imageUploadService.consume(
                    request.getUploadId(), request.getBackgroundKey(), userId);
            map.updateBackgroundKey(fileKey);
            if (oldBackgroundKey != null) {
                fileCleanupService.scheduleDelete(oldBackgroundKey);
            }
        }
    }

    @Override
    public List<MapInfoDto> getMapList(Long userId) {
        User user = userRepository.findById(userId)
                .orElseThrow(() -> new UserException(USER_NOT_FOUND));

        List<MapMember> mapMembers = mapMemberRepository.findAllByUserWithMap(user).stream()
                .filter(mm -> mm.getMapMemberRole() != PENDING)
                .toList();

        List<Long> mapIds = mapMembers.stream()
                .map(mm -> mm.getMap().getMapId())
                .toList();

        java.util.Map<Long, Long> countMap = new HashMap<>();
        mapMemberRepository.countMembersByMapIds(mapIds, PENDING)
                .forEach(row -> countMap.put((Long) row[0], (Long) row[1]));

        return mapMembers.stream()
                .map(mm -> MapInfoDto.from(mm, countMap.getOrDefault(mm.getMap().getMapId(), 0L),
                        s3Service::getFileUrl))
                .toList();
    }

    @Override
    public MapInfoDto getMapDetail(Long mapId, Long userId) {
        MapMember mapMember = mapMemberRepository.findByMap_MapIdAndUser_UserId(mapId, userId)
                .filter(m -> m.getMapMemberRole() != PENDING)
                .orElseThrow(() -> new MapException(NOT_MAP_MEMBER));

        long memberCount = mapMemberRepository.countByMap_MapIdAndMapMemberRoleNot(mapId, PENDING);
        return MapInfoDto.from(mapMember, memberCount, s3Service::getFileUrl);
    }

    @Override
    @Transactional
    public void inviteFriend(Long mapId, InviteFriendRequestDto request, Long userId) {
        User inviter = userRepository.findById(userId)
                .orElseThrow(() -> new UserException(USER_NOT_FOUND));

        MapMember invitingMember = mapMemberRepository.findByMap_MapIdAndUser_UserId(mapId, inviter.getUserId())
                .orElseThrow(() -> new MapException(NOT_MAP_MEMBER));

        if (invitingMember.getMapMemberRole() != OWNER && invitingMember.getMapMemberRole() != EDITOR) {
            throw new MapException(NO_INVITE_PERMISSION);
        }

        User friendToInvite = userRepository.findById(request.getFriendId())
                .orElseThrow(() -> new UserException(USER_NOT_FOUND));

        if (!friendshipRepository.existsFriendship(inviter, friendToInvite, FriendshipStatus.ACCEPTED)) {
            throw new FriendException(INVALID_FRIENDSHIP_ID);
        }

        mapMemberRepository.findByMap_MapIdAndUser_UserId(mapId, friendToInvite.getUserId()).ifPresent(m -> {
            throw new MapException(ALREADY_MAP_MEMBER);
        });

        Map map = invitingMember.getMap();
        MapMember newMember = MapMember.from(map, friendToInvite, inviter, PENDING);

        try {
            mapMemberRepository.save(newMember);
            mapMemberRepository.flush();
        } catch (DataIntegrityViolationException e) {
            throw new MapException(MAP_INVITATION_CONFLICT);
        }
    }

    @Override
    @Transactional
    public void acceptInvitation(Long mapMemberId, Long userId) {
        User user = userRepository.findById(userId)
                .orElseThrow(() -> new UserException(USER_NOT_FOUND));

        MapMember mapMember = mapMemberRepository.findById(mapMemberId)
                .orElseThrow(() -> new MapException(INVITATION_NOT_FOUND));

        if (!mapMember.isInvitedUser(user)) {
            throw new MapException(NOT_INVITED_USER);
        }

        if (!mapMember.isPending()) {
            throw new MapException(INVITATION_NOT_FOUND);
        }

        mapMember.accept();
    }

    @Override
    @Transactional
    public void rejectInvitation(Long mapMemberId, Long userId) {
        User user = userRepository.findById(userId)
                .orElseThrow(() -> new UserException(USER_NOT_FOUND));

        MapMember mapMember = mapMemberRepository.findById(mapMemberId)
                .orElseThrow(() -> new MapException(INVITATION_NOT_FOUND));

        if (!mapMember.isInvitedUser(user)) {
            throw new MapException(NOT_INVITED_USER);
        }

        if (!mapMember.isPending()) {
            throw new MapException(INVITATION_NOT_FOUND);
        }

        mapMemberRepository.delete(mapMember);
    }

    @Override
    public List<MapMemberDto> getMapMembers(Long mapId, Long userId) {
        mapMemberRepository.findByMap_MapIdAndUser_UserId(mapId, userId)
                .filter(m -> m.getMapMemberRole() != PENDING)
                .orElseThrow(() -> new MapException(NOT_MAP_MEMBER));

        return mapMemberRepository.findAllByMap_MapIdAndMapMemberRoleNot(mapId, PENDING).stream()
                .map(mm -> MapMemberDto.from(mm, s3Service::getFileUrl))
                .toList();
    }

    @Override
    public List<MapInvitationDto> getInvitationList(Long userId) {
        User user = userRepository.findById(userId)
                .orElseThrow(() -> new UserException(USER_NOT_FOUND));
        return mapMemberRepository.findAllByUserAndMapMemberRole(user, PENDING).stream()
                .map(MapInvitationDto::from)
                .collect(Collectors.toList());
    }
}
