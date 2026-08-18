package com.couplemap.global.exception.code;

import lombok.Getter;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;

import static org.springframework.http.HttpStatus.BAD_REQUEST;
import static org.springframework.http.HttpStatus.INTERNAL_SERVER_ERROR;

@RequiredArgsConstructor
@Getter
public enum S3ErrorCode implements ErrorCode {
    // 파일 관련
    FILE_IS_EMPTY(BAD_REQUEST, "파일이 비어있습니다."),
    // 이미지(프로필, 배경)와 미디어(추억 첨부)의 상한이 달라 한쪽 숫자만 적으면 거짓이 된다.
    FILE_SIZE_EXCEEDED(BAD_REQUEST, "파일 크기 제한을 초과했습니다. (이미지 5MB, 동영상,오디오 100MB)"),
    // 허용 목록도 경로별로 다르다. 이미지 목록만 적으면 미디어 경로에서 거짓이 된다.
    INVALID_FILE_TYPE(BAD_REQUEST, "지원하지 않는 파일 형식입니다. (프로필,배경: JPG, PNG / 추억 첨부: JPG, PNG, MP4, MOV, MP3, M4A)"),
    INVALID_FILE_NAME(BAD_REQUEST, "올바른 파일명이 아닙니다."),
    INVALID_FILE_EXTENSION(BAD_REQUEST, "파일 확장자가 올바르지 않습니다."),


    // S3 관련
    S3_UPLOAD_FAILED(INTERNAL_SERVER_ERROR, "S3 파일 업로드에 실패했습니다."),
    S3_DELETE_FAILED(INTERNAL_SERVER_ERROR, "S3 파일 삭제에 실패했습니다."),
    S3_PRESIGN_FAILED(INTERNAL_SERVER_ERROR, "업로드 URL 발급에 실패했습니다."),

    UPLOAD_SESSION_NOT_FOUND(BAD_REQUEST, "만료되었거나 존재하지 않는 업로드입니다."),
    UPLOAD_SESSION_MISMATCH(BAD_REQUEST, "업로드 정보가 일치하지 않습니다."),
    UPLOAD_FILE_REQUIRED(BAD_REQUEST, "업로드할 파일 정보가 필요합니다.");

    private final HttpStatus httpStatus;
    private final String message;

    @Override
    public String getCodeName() {
        return this.name();
    }
}
