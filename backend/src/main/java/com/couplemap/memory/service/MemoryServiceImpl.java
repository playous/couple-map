package com.couplemap.memory.service;

import com.couplemap.global.exception.code.MemoryErrorCode;
import com.couplemap.global.exception.code.S3ErrorCode;
import com.couplemap.global.exception.exceptions.MapException;
import com.couplemap.global.exception.exceptions.MemoryException;
import com.couplemap.global.exception.exceptions.S3Exception;
import com.couplemap.global.exception.exceptions.UserException;
import com.couplemap.global.filecleanup.FileCleanupService;
import com.couplemap.global.s3.S3PresignedDto;
import com.couplemap.global.s3.S3Service;
import com.couplemap.map.domain.Map;
import com.couplemap.map.domain.MapMember;
import com.couplemap.map.repository.MapMemberRepository;
import com.couplemap.map.repository.MapRepository;
import com.couplemap.mediafile.domain.MediaFile;
import com.couplemap.mediafile.domain.MediaFileType;
import com.couplemap.mediafile.repository.MediaFileRepository;
import com.couplemap.memory.domain.Memory;
import com.couplemap.memory.domain.UploadSession;
import com.couplemap.memory.dto.CalendarMemoryResponseDto;
import com.couplemap.memory.dto.CompleteUploadRequestDto;
import com.couplemap.memory.dto.CreateMemoryRequestDto;
import com.couplemap.memory.dto.MediaFileDto;
import com.couplemap.memory.dto.MemoryDetailResponseDto;
import com.couplemap.memory.dto.MemoryListResponseDto;
import com.couplemap.memory.dto.MemoryMarkerResponseDto;
import com.couplemap.memory.dto.UpdateMemoryRequestDto;
import com.couplemap.memory.dto.UploadUrlRequestDto;
import com.couplemap.memory.dto.UploadUrlResponseDto;
import com.couplemap.memory.repository.MemoryRepository;
import com.couplemap.memory.repository.UploadSessionRepository;
import com.couplemap.user.domain.User;
import com.couplemap.user.repository.UserRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.domain.Pageable;
import org.springframework.data.domain.Slice;
import org.springframework.data.domain.SliceImpl;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Duration;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import java.util.stream.Collectors;

import static com.couplemap.global.exception.code.MapErrorCode.*;
import static com.couplemap.global.exception.code.MemoryErrorCode.*;
import static com.couplemap.global.exception.code.UserErrorCode.USER_NOT_FOUND;
import static com.couplemap.map.domain.MapMemberRole.EDITOR;
import static com.couplemap.map.domain.MapMemberRole.OWNER;
import static com.couplemap.map.domain.MapMemberRole.PENDING;

@Service
@RequiredArgsConstructor
@Transactional(readOnly = true)
public class MemoryServiceImpl implements MemoryService {

    private final MemoryRepository memoryRepository;
    private final MapRepository mapRepository;
    private final UserRepository userRepository;
    private final MapMemberRepository mapMemberRepository;
    private final S3Service s3Service;
    private final FileCleanupService fileCleanupService;
    private final MediaFileRepository mediaFileRepository;
    private final UploadSessionRepository uploadSessionRepository;

    @Value("${upload.session-ttl}")
    private Duration sessionTtl;
    @Value("${upload.orphan-grace}")
    private Duration orphanGrace;

    @Override
    @Transactional
    public Long createMemory(Long mapId, CreateMemoryRequestDto request, Long userId) {
        User user = userRepository.findById(userId)
                .orElseThrow(() -> new UserException(USER_NOT_FOUND));

        validateWritableMember(mapId, userId);

        Map map = mapRepository.findById(mapId)
                .orElseThrow(() -> new MapException(MAP_NOT_FOUND));

        Memory newMemory = Memory.from(request, map, user);
        memoryRepository.save(newMemory);

        return newMemory.getMemoryId();
    }

    @Override
    @Transactional
    public UploadUrlResponseDto issueUploadUrls(Long mapId, UploadUrlRequestDto request, Long userId) {
        validateWritableMember(mapId, userId);

        List<S3PresignedDto> presigned = request.getFiles().stream()
                .map(f -> s3Service.presignMediaUpload(f.getFilename(), f.getContentType(), f.getSize()))
                .toList();

        List<UploadSession.UploadFile> sessionFiles = new ArrayList<>();
        for (int i = 0; i < presigned.size(); i++) {
            UploadUrlRequestDto.FileSpec spec = request.getFiles().get(i);
            sessionFiles.add(new UploadSession.UploadFile(
                    presigned.get(i).getFileKey(), spec.getFilename(), spec.getContentType(), spec.getSize()));
        }

        String uploadId = UUID.randomUUID().toString();
        uploadSessionRepository.save(UploadSession.of(uploadId, userId, mapId,
                UploadSession.PURPOSE_MEMORY, sessionFiles, sessionTtl.toSeconds()));

        fileCleanupService.schedulePendingUpload(
                presigned.stream().map(S3PresignedDto::getFileKey).toList(),
                LocalDateTime.now().plus(orphanGrace));

        return UploadUrlResponseDto.of(uploadId, presigned);
    }

    @Override
    @Transactional
    public Long completeUpload(Long mapId, CompleteUploadRequestDto request, Long userId) {
        User user = userRepository.findById(userId)
                .orElseThrow(() -> new UserException(USER_NOT_FOUND));

        validateWritableMember(mapId, userId);

        Map map = mapRepository.findById(mapId)
                .orElseThrow(() -> new MapException(MAP_NOT_FOUND));

        UploadSession session = uploadSessionRepository.findById(request.getUploadId())
                .orElseThrow(() -> new S3Exception(S3ErrorCode.UPLOAD_SESSION_NOT_FOUND));

        if (!session.isOwnedBy(userId, mapId)) {
            throw new S3Exception(S3ErrorCode.UPLOAD_SESSION_MISMATCH);
        }

        Memory memory = Memory.from(request.getRequest(), map, user);
        memoryRepository.save(memory);

        List<CompleteUploadRequestDto.FileRef> refs =
                request.getFiles() == null ? List.of() : request.getFiles();

        if (!refs.isEmpty()) {
            List<MediaFile> mediaFiles = refs.stream()
                    .map(ref -> toMediaFile(memory, session, ref, ref.getDisplayOrder()))
                    .toList();
            mediaFileRepository.saveAll(mediaFiles);
        }

        // 실제로 쓴 키만 회수 예약을 푼다. 발급만 받고 안 쓴 키는 배치가 지운다
        fileCleanupService.cancelPendingUpload(
                refs.stream().map(CompleteUploadRequestDto.FileRef::getFileKey).toList());
        uploadSessionRepository.deleteById(request.getUploadId());

        return memory.getMemoryId();
    }

    private MediaFile toMediaFile(Memory memory, UploadSession session,
                                  CompleteUploadRequestDto.FileRef ref, int displayOrder) {
        UploadSession.UploadFile issued = session.find(ref.getFileKey())
                .orElseThrow(() -> new S3Exception(S3ErrorCode.UPLOAD_SESSION_MISMATCH));

        return MediaFile.of(
                memory,
                issued.getFileKey(),
                issued.getFilename(),
                mediaFileTypeOf(issued.getContentType()),
                issued.getSize(),
                displayOrder);
    }

    private int maxDisplayOrder(Long memoryId) {
        return mediaFileRepository.findByMemoryIdOrderByDisplayOrder(memoryId).stream()
                .mapToInt(MediaFile::getDisplayOrder)
                .max()
                .orElse(0);
    }

    @Override
    public Slice<MemoryListResponseDto> getMemoryList(Long mapId, Long userId, Pageable pageable) {
        // 1. 권한 검증
        validateActiveMember(mapId, userId);

        // 2. 페이징 조회
        Slice<Memory> memorySlice = memoryRepository.findByMap_MapId(mapId, pageable);
        List<Memory> memories = memorySlice.getContent();

        // 3. 썸네일 일괄 조회 (추억당 1장만, 전체 미디어 로딩 없음)
        List<Long> memoryIds = memories.stream().map(Memory::getMemoryId).collect(Collectors.toList());

        java.util.Map<Long, String> thumbnailMap = mediaFileRepository.findThumbnailsByMemoryIds(memoryIds).stream()
                .collect(Collectors.toMap(
                        mf -> mf.getMemory().getMemoryId(),
                        mf -> s3Service.getFileUrl(mf.getFileKey())
                ));

        List<MemoryListResponseDto> content = memories.stream()
                .map(memory -> new MemoryListResponseDto(memory, thumbnailMap.get(memory.getMemoryId())))
                .collect(Collectors.toList());

        return new SliceImpl<>(content, pageable, memorySlice.hasNext());
    }

    @Override
    public List<MemoryMarkerResponseDto> getMemoryMarkers(Long mapId, Long userId) {
        // 1. 권한 검증
        validateActiveMember(mapId, userId);

        // 2. 좌표만 조회 (DTO 프로젝션, 엔티티 로딩 없음)
        return memoryRepository.findMarkersByMapId(mapId);
    }

    public MemoryDetailResponseDto getMemoryDetail(Long mapId, Long memoryId, Long userId) {
        Memory memory = validateAndGetMemory(mapId, memoryId, userId);

        List<MediaFileDto> mediaFiles = mediaFileRepository.findByMemoryIdOrderByDisplayOrder(memoryId)
                .stream()
                .map(mf -> new MediaFileDto(mf, s3Service.getFileUrl(mf.getFileKey())))
                .collect(Collectors.toList());

        return new MemoryDetailResponseDto(memory, mediaFiles);
    }

    @Override
    @Transactional
    public void deleteMemory(Long mapId, Long memoryId, Long userId) {
        Memory memory = validateAndGetMemory(mapId, memoryId, userId);
        validateMemoryOwnership(memory, userId, NO_PERMISSION_TO_DELETE);

        // 파일 삭제
        List<MediaFile> filesToDelete = mediaFileRepository.findByMemoryId(memoryId);
        fileCleanupService.scheduleDeleteAll(filesToDelete.stream().map(MediaFile::getFileKey).toList());
        mediaFileRepository.deleteAll(filesToDelete);

        // Memory 삭제
        memoryRepository.delete(memory);
    }

    @Override
    @Transactional
    public Long updateMemory(Long mapId, Long memoryId, UpdateMemoryRequestDto request, Long userId) {

        Memory memory = validateAndGetMemory(mapId, memoryId, userId);
        validateMemoryOwnership(memory, userId, NO_PERMISSION_TO_UPDATE);

        memory.update(request);

        // 기존 파일 삭제
        if (request.getDeleteFileIds() != null && !request.getDeleteFileIds().isEmpty()) {
            List<MediaFile> filesToDelete = mediaFileRepository.findAllByIdsAndMemoryId(request.getDeleteFileIds(), memoryId);

            if (filesToDelete.size() != request.getDeleteFileIds().size()) {
                throw new MemoryException(INVALID_MEDIA_FILE);
            }

            fileCleanupService.scheduleDeleteAll(filesToDelete.stream().map(MediaFile::getFileKey).toList());

            mediaFileRepository.deleteAll(filesToDelete);
        }

        // 새 파일 추가 — presigned로 이미 S3에 올라간 키를 받는다
        List<CompleteUploadRequestDto.FileRef> newRefs =
                request.getFiles() == null ? List.of() : request.getFiles();

        if (!newRefs.isEmpty()) {
            UploadSession session = uploadSessionRepository.findById(request.getUploadId())
                    .orElseThrow(() -> new S3Exception(S3ErrorCode.UPLOAD_SESSION_NOT_FOUND));

            if (!session.isOwnedBy(userId, mapId)) {
                throw new S3Exception(S3ErrorCode.UPLOAD_SESSION_MISMATCH);
            }

            int displayOrder = maxDisplayOrder(memoryId) + 1;
            List<MediaFile> newFiles = new ArrayList<>();
            for (CompleteUploadRequestDto.FileRef ref : newRefs) {
                newFiles.add(toMediaFile(memory, session, ref, displayOrder++));
            }
            mediaFileRepository.saveAll(newFiles);

            fileCleanupService.cancelPendingUpload(
                    newRefs.stream().map(CompleteUploadRequestDto.FileRef::getFileKey).toList());
            uploadSessionRepository.deleteById(request.getUploadId());
        }

        return memory.getMemoryId();
    }

    private MediaFileType mediaFileTypeOf(String contentType) {
        if (contentType == null) {
            throw new S3Exception(S3ErrorCode.INVALID_FILE_TYPE);
        }

        if (contentType.startsWith("image/")) {
            return MediaFileType.IMAGE;
        } else if (contentType.startsWith("video/")) {
            return MediaFileType.VIDEO;
        } else if (contentType.startsWith("audio/")) {
            return MediaFileType.AUDIO;
        } else {
            throw new S3Exception(S3ErrorCode.INVALID_FILE_TYPE);
        }
    }

    private void validateWritableMember(Long mapId, Long userId) {
        MapMember mapMember = mapMemberRepository.findByMap_MapIdAndUser_UserId(mapId, userId)
                .orElseThrow(() -> new MapException(NOT_MAP_MEMBER));

        if (mapMember.getMapMemberRole() != OWNER && mapMember.getMapMemberRole() != EDITOR) {
            throw new MapException(NOT_MAP_MEMBER);
        }
    }

    // 조회 권한 검증 — 행 존재만 보면 수락 전 PENDING 멤버가 추억, 좌표를 전부 열람한다
    private void validateActiveMember(Long mapId, Long userId) {
        mapMemberRepository.findByMap_MapIdAndUser_UserId(mapId, userId)
                .filter(mapMember -> mapMember.getMapMemberRole() != PENDING)
                .orElseThrow(() -> new MapException(NOT_MAP_MEMBER));
    }

    private Memory validateAndGetMemory(Long mapId, Long memoryId, Long userId) {
        // 맵 멤버 검증
        validateActiveMember(mapId, userId);

        // Memory 조회
        Memory memory = memoryRepository.findById(memoryId)
                .orElseThrow(() -> new MemoryException(MEMORY_NOT_FOUND));

        // Memory가 해당 Map에 속하는지 검증
        if (!memory.getMap().getMapId().equals(mapId)) {
            throw new MemoryException(MEMORY_NOT_FOUND);
        }

        return memory;
    }

    @Override
    public List<CalendarMemoryResponseDto> getCalendarMemories(int year, Integer month, Long userId) {
        if (month != null && (month < 1 || month > 12)) {
            throw new MemoryException(INVALID_MONTH);
        }

        // 컬럼에 YEAR()를 씌우면 인덱스를 못 타므로 범위로 바꿔서 넘긴다
        // month가 있으면 그 달만 — 화면이 한 달씩 보여주는데 연도 전체를 만들면 응답 대부분이 버려진다
        LocalDate from = (month == null) ? LocalDate.of(year, 1, 1) : LocalDate.of(year, month, 1);
        LocalDate to = (month == null) ? LocalDate.of(year, 12, 31) : from.withDayOfMonth(from.lengthOfMonth());
        List<Memory> memories = memoryRepository.findAllByUserIdAndYear(userId, from, to, List.of(OWNER, EDITOR));

        List<Long> memoryIds = memories.stream().map(Memory::getMemoryId).collect(Collectors.toList());

        if (memoryIds.isEmpty()) {
            return List.of();
        }

        // 썸네일 일괄 조회 (추억당 1장만, 전체 미디어 로딩 없음)
        java.util.Map<Long, String> thumbnailMap = mediaFileRepository.findThumbnailsByMemoryIds(memoryIds).stream()
                .collect(Collectors.toMap(
                        mf -> mf.getMemory().getMemoryId(),
                        mf -> s3Service.getFileUrl(mf.getFileKey())
                ));

        return memories.stream()
                .map(memory -> new CalendarMemoryResponseDto(memory, thumbnailMap.get(memory.getMemoryId())))
                .collect(Collectors.toList());
    }

    private void validateMemoryOwnership(Memory memory, Long userId, MemoryErrorCode errorCode) {
        if (!memory.getUser().getUserId().equals(userId)) {
            throw new MemoryException(errorCode);
        }
    }

}
