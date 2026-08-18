package com.couplemap.global.s3;

import com.couplemap.global.exception.exceptions.S3Exception;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;

import static org.assertj.core.api.Assertions.assertThat;
import static org.junit.jupiter.api.Assertions.assertThrows;

// presign은 로컬 서명이라 S3 호출이 없다. 검증 로직과 URL 형태만 확인한다
@SpringBootTest
class S3ServiceImplTest {

    private static final long ONE_MB = 1024 * 1024;

    @Autowired
    private S3ServiceImpl s3ServiceImpl;

    @Nested
    @DisplayName("이미지 업로드 URL 발급")
    class PresignImage {

        @Test
        @DisplayName("성공 - profile 경로와 확장자가 유지된다")
        void success() {
            S3PresignedDto result = s3ServiceImpl.presignImageUpload("test.png", "image/png", ONE_MB);

            assertThat(result.getFileKey()).contains("profile/");
            assertThat(result.getFileKey()).endsWith(".png");
            assertThat(result.getUrl()).contains("X-Amz-Signature");
            assertThat(result.getUrl()).contains("X-Amz-Expires");
        }

        @Test
        @DisplayName("성공 - 점이 여러 개인 파일명도 마지막 확장자를 쓴다")
        void multiDotFilename() {
            S3PresignedDto result = s3ServiceImpl.presignImageUpload("my.photo.jpg", "image/jpeg", ONE_MB);

            assertThat(result.getFileKey()).endsWith(".jpg");
        }

        @Test
        @DisplayName("실패 - 크기가 0이면 거부한다")
        void zeroSize() {
            assertThrows(S3Exception.class,
                    () -> s3ServiceImpl.presignImageUpload("test.png", "image/png", 0));
        }

        @Test
        @DisplayName("실패 - 5MB를 넘으면 거부한다")
        void sizeExceeded() {
            assertThrows(S3Exception.class,
                    () -> s3ServiceImpl.presignImageUpload("test.png", "image/png", 6 * ONE_MB));
        }

        @Test
        @DisplayName("실패 - 허용하지 않는 Content-Type")
        void invalidContentType() {
            assertThrows(S3Exception.class,
                    () -> s3ServiceImpl.presignImageUpload("test.pdf", "application/pdf", ONE_MB));
        }

        @Test
        @DisplayName("실패 - 확장자가 없는 파일명")
        void noExtension() {
            assertThrows(S3Exception.class,
                    () -> s3ServiceImpl.presignImageUpload("noext", "image/png", ONE_MB));
        }

        @Test
        @DisplayName("실패 - Content-Type과 맞지 않는 확장자")
        void invalidExtension() {
            assertThrows(S3Exception.class,
                    () -> s3ServiceImpl.presignImageUpload("test.gif", "image/png", ONE_MB));
        }

        @Test
        @DisplayName("실패 - 이미지에는 동영상을 허용하지 않는다")
        void videoRejected() {
            assertThrows(S3Exception.class,
                    () -> s3ServiceImpl.presignImageUpload("clip.mp4", "video/mp4", ONE_MB));
        }
    }

    @Nested
    @DisplayName("미디어 업로드 URL 발급")
    class PresignMedia {

        @Test
        @DisplayName("성공 - memory 경로를 쓴다")
        void success() {
            S3PresignedDto result = s3ServiceImpl.presignMediaUpload("photo.jpg", "image/jpeg", ONE_MB);

            assertThat(result.getFileKey()).contains("memory/");
            assertThat(result.getFileKey()).endsWith(".jpg");
            assertThat(result.getUrl()).contains("X-Amz-Signature");
        }

        @Test
        @DisplayName("성공 - mp3")
        void mp3() {
            S3PresignedDto result = s3ServiceImpl.presignMediaUpload("audio.mp3", "audio/mpeg", 3 * ONE_MB);

            assertThat(result.getFileKey()).endsWith(".mp3");
        }

        @Test
        @DisplayName("성공 - mp4")
        void mp4() {
            S3PresignedDto result = s3ServiceImpl.presignMediaUpload("clip.mp4", "video/mp4", 10 * ONE_MB);

            assertThat(result.getFileKey()).endsWith(".mp4");
        }

        @Test
        @DisplayName("성공 - mov")
        void mov() {
            S3PresignedDto result = s3ServiceImpl.presignMediaUpload("clip.mov", "video/quicktime", 10 * ONE_MB);

            assertThat(result.getFileKey()).endsWith(".mov");
        }

        @Test
        @DisplayName("성공 - m4a")
        void m4a() {
            S3PresignedDto result = s3ServiceImpl.presignMediaUpload("audio.m4a", "audio/x-m4a", ONE_MB);

            assertThat(result.getFileKey()).endsWith(".m4a");
        }

        @Test
        @DisplayName("실패 - 100MB를 넘으면 거부한다")
        void sizeExceeded() {
            assertThrows(S3Exception.class,
                    () -> s3ServiceImpl.presignMediaUpload("clip.mp4", "video/mp4", 101 * ONE_MB));
        }

        @Test
        @DisplayName("실패 - 허용하지 않는 Content-Type")
        void invalidContentType() {
            assertThrows(S3Exception.class,
                    () -> s3ServiceImpl.presignMediaUpload("doc.pdf", "application/pdf", ONE_MB));
        }

        @Test
        @DisplayName("발급마다 다른 키를 만든다")
        void uniqueKeys() {
            String first = s3ServiceImpl.presignMediaUpload("photo.jpg", "image/jpeg", ONE_MB).getFileKey();
            String second = s3ServiceImpl.presignMediaUpload("photo.jpg", "image/jpeg", ONE_MB).getFileKey();

            assertThat(first).isNotEqualTo(second);
        }
    }

    @Nested
    @DisplayName("조회 URL 발급")
    class GetFileUrl {

        @Test
        @DisplayName("서명된 조회 URL을 만든다")
        void signedUrl() {
            String url = s3ServiceImpl.getFileUrl("memory/sample.jpg");

            assertThat(url).contains("X-Amz-Signature");
            assertThat(url).contains("X-Amz-Expires");
        }

        @Test
        @DisplayName("키가 없으면 null을 반환한다 - 프로필 미설정 사용자")
        void nullKey() {
            assertThat(s3ServiceImpl.getFileUrl(null)).isNull();
        }
    }
}
