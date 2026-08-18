package com.couplemap.map.controller;

import com.couplemap.global.response.ApiResponse;
import com.couplemap.map.dto.*;
import com.couplemap.map.service.MapService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import lombok.RequiredArgsConstructor;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.*;

import java.net.URI;
import java.util.List;

@Tag(name = "Map", description = "지도 관리 API")
@RestController
@RequiredArgsConstructor
@RequestMapping("/api/map")
public class MapController {

    private final MapService mapService;

    @Operation(summary = "지도 생성", description = "배경 이미지는 /api/uploads/image로 먼저 올리고 키만 전달합니다.")
    @PostMapping
    public ResponseEntity<ApiResponse<Long>> createMap(
            @Valid @RequestBody CreateMapRequestDto request,
            @AuthenticationPrincipal(expression = "userId") Long userId) {
        Long mapId = mapService.createMap(request, userId);
        return ResponseEntity.created(URI.create("/api/map/" + mapId))
                .body(ApiResponse.success(mapId, "지도가 성공적으로 생성되었습니다."));
    }

    @Operation(summary = "지도 조회")
    @GetMapping("/{mapId}")
    public ResponseEntity<ApiResponse<MapInfoDto>> getMap(@PathVariable Long mapId,
                                                      @AuthenticationPrincipal(expression = "userId") Long userId) {
        MapInfoDto mapDetail = mapService.getMapDetail(mapId, userId);
        return ResponseEntity.ok(ApiResponse.success(mapDetail, "지도 조회가 완료되었습니다."));
    }

    @Operation(summary = "지도 삭제")
    @DeleteMapping("/{mapId}")
    public ResponseEntity<ApiResponse<Void>> deleteMap(@PathVariable Long mapId, @AuthenticationPrincipal(expression = "userId") Long userId) {
        mapService.deleteMap(mapId, userId);
        return ResponseEntity.ok(ApiResponse.success("지도를 삭제했습니다."));
    }

    @Operation(summary = "지도 수정")
    @PutMapping("/{mapId}")
    public ResponseEntity<ApiResponse<Void>> updateMap(
            @PathVariable Long mapId,
            @Valid @RequestBody UpdateMapRequestDto request,
            @AuthenticationPrincipal(expression = "userId") Long userId) {
        mapService.updateMap(mapId, request, userId);
        return ResponseEntity.ok(ApiResponse.success("지도를 수정했습니다."));
    }

    @Operation(summary = "지도 목록 조회")
    @GetMapping
    public ResponseEntity<ApiResponse<List<MapInfoDto>>> getMapList(@AuthenticationPrincipal(expression = "userId") Long userId) {
        List<MapInfoDto> mapList = mapService.getMapList(userId);
        return ResponseEntity.ok(ApiResponse.success(mapList, "지도 목록 조회가 완료되었습니다."));
    }

    @Operation(summary = "지도 멤버 목록 조회")
    @GetMapping("/{mapId}/members")
    public ResponseEntity<ApiResponse<List<MapMemberDto>>> getMapMembers(@PathVariable Long mapId,
                                                                         @AuthenticationPrincipal(expression = "userId") Long userId) {
        List<MapMemberDto> members = mapService.getMapMembers(mapId, userId);
        return ResponseEntity.ok(ApiResponse.success(members, "지도 멤버 목록 조회가 완료되었습니다."));
    }

    @Operation(summary = "지도에 친구 초대")
    @PostMapping("/{mapId}/invite")
    public ResponseEntity<ApiResponse<Void>> inviteFriend(@PathVariable Long mapId,
                                                        @Valid @RequestBody InviteFriendRequestDto request,
                                                        @AuthenticationPrincipal(expression = "userId") Long userId) {
        mapService.inviteFriend(mapId, request, userId);
        return ResponseEntity.ok(ApiResponse.success("지도에 친구를 초대했습니다."));
    }

    @Operation(summary = "지도 초대 수락")
    @PostMapping("/member/{mapMemberId}/accept")
    public ResponseEntity<ApiResponse<Void>> acceptInvitation(@PathVariable Long mapMemberId, @AuthenticationPrincipal(expression = "userId") Long userId) {
        mapService.acceptInvitation(mapMemberId, userId);
        return ResponseEntity.ok(ApiResponse.success("초대를 수락했습니다."));
    }

    @Operation(summary = "지도 초대 거절")
    @PostMapping("/member/{mapMemberId}/reject")
    public ResponseEntity<ApiResponse<Void>> rejectInvitation(@PathVariable Long mapMemberId, @AuthenticationPrincipal(expression = "userId") Long userId) {
        mapService.rejectInvitation(mapMemberId, userId);
        return ResponseEntity.ok(ApiResponse.success("초대를 거절했습니다."));
    }

    @Operation(summary = "받은 초대 목록 조회")
    @GetMapping("/invitations")
    public ResponseEntity<ApiResponse<List<MapInvitationDto>>> getInvitationList(@AuthenticationPrincipal(expression = "userId") Long userId) {
        List<MapInvitationDto> invitationList = mapService.getInvitationList(userId);
        return ResponseEntity.ok(ApiResponse.success(invitationList, "받은 초대 목록 조회가 완료되었습니다."));
    }
}
