package com.couplemap.global.exception.code;

import lombok.Getter;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;

@Getter
@RequiredArgsConstructor
public enum MemoryErrorCode implements ErrorCode {

    MEMORY_NOT_FOUND(HttpStatus.NOT_FOUND, "존재하지 않는 추억입니다."),
    NO_PERMISSION_TO_DELETE(HttpStatus.FORBIDDEN, "추억을 삭제할 권한이 없습니다."),
    NO_PERMISSION_TO_UPDATE(HttpStatus.FORBIDDEN, "추억을 수정할 권한이 없습니다."),
    INVALID_MEDIA_FILE(HttpStatus.BAD_REQUEST, "해당 추억에 속하지 않는 파일입니다."),
    INVALID_MONTH(HttpStatus.BAD_REQUEST, "월은 1에서 12 사이여야 합니다.");

    private final HttpStatus httpStatus;
    private final String message;

    @Override
    public String getCodeName() {
        return this.name();
    }
}
