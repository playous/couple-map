package com.couplemap.global.exception;

import com.couplemap.global.exception.code.DtoErrorCode;
import com.couplemap.global.exception.exceptions.BaseException;
import com.couplemap.global.response.ApiResponse;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.ResponseEntity;
import org.springframework.validation.FieldError;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

import java.util.HashMap;
import java.util.Map;

@Slf4j
@RestControllerAdvice
public class GlobalExceptionHandler {

    @ExceptionHandler(BaseException.class)
    public ResponseEntity<ApiResponse<Void>> handleBaseException(BaseException e) {
        if (e.getCode().getHttpStatus().is5xxServerError()) {
            log.error("BaseException: {} - {}", e.getCode().getCodeName(), e.getMessage(), e);
        } else {
            log.warn("BaseException: {} - {}", e.getCode().getCodeName(), e.getMessage());
        }
        return ResponseEntity
                .status(e.getCode().getHttpStatus())
                .body(ApiResponse.fail(e.getCode()));
    }

    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ResponseEntity<ApiResponse<Map<String, String>>> handleValidationException(
            MethodArgumentNotValidException ex) {

        log.warn("Validation failed: {}", ex.getMessage());

        Map<String, String> errors = new HashMap<>();
        ex.getBindingResult().getAllErrors().forEach(error -> {
            String fieldName = ((FieldError) error).getField();
            String errorMessage = error.getDefaultMessage();
            errors.put(fieldName, errorMessage);
        });

        return ResponseEntity
                .status(DtoErrorCode.INVALID_INPUT_VALUE.getHttpStatus())
                .body(ApiResponse.fail(DtoErrorCode.INVALID_INPUT_VALUE, errors));
    }

}
