-- =============================================================
-- 부하 테스트 생성 데이터 정리 (시드 v3 기준)
-- =============================================================
-- journey.js는 기본으로 생성 데이터를 정리하지 않는다. teardown이 서버에
-- 부하를 다시 걸고 오래 걸리기 때문이다. 대신 라운드가 바뀔 때와
-- 무효(INVALID) 실행 뒤에 이 파일을 실행해 시드 상태를 복원한다.
-- (docs/load-test-plan.md 7절)
--
-- 시드 경계 (load-test-seed.sql v3):
--   memories  1 ~ 290,000
--   maps      1 ~ 5,000
-- 이 경계보다 큰 ID는 전부 테스트 중 생성된 것이다.
--
-- 테스트가 만드는 것:
--   POST_memory_text      지도 4,001~4,700 에 추억
--   POST_memory_complete  지도 4,701~4,900 에 추억 + media_files + S3 객체
--   POST_map              map_id 5,001 이상 + map_members
--   PUT_memory            시드 추억의 title, content, place_name 을 덮어씀
--   업로드 발급           file_cleanup_task 에 회수 예약 행
-- =============================================================

-- ── 1. 테스트가 만든 행 삭제 ─────────────────────────────────
-- file_cleanup_task는 통째로 비운다. 시드가 만드는 행이 없고,
-- 남겨두면 배치가 S3를 건드려 다음 측정을 오염시킨다.
-- TRUNCATE를 쓰는 이유: WHERE 없는 DELETE는 Workbench safe update mode에 막힌다
TRUNCATE TABLE file_cleanup_task;

DELETE FROM media_files WHERE memory_id > 290000;
DELETE FROM memories    WHERE memory_id > 290000;

DELETE FROM map_members WHERE map_id > 5000;
DELETE FROM maps        WHERE map_id > 5000;

-- ── 2. 수정 부하가 덮어쓴 시드 추억 복원 ─────────────────────
-- memoryDate와 category는 journey.js가 시드와 같은 값으로 보내므로(멱등)
-- 복원할 필요가 없다. title, content, place_name만 되돌린다.
-- 이걸 놔두면 응답 크기가 조금씩 달라져 라운드 간 비교에 잡음이 낀다.
UPDATE memories
SET title      = CONCAT('추억 ', memory_id),
    content    = CONCAT('추억 내용입니다. (지도 ', map_id, ')'),
    place_name = ELT((memory_id % 10) + 1,
                     '서울 강남구', '부산 해운대', '제주 서귀포', '인천 송도', '수원 화성',
                     '대전 유성구', '대구 동성로', '광주 무등산', '강릉 경포대', '전주 한옥마을')
-- memory_id 조건은 safe update mode 통과용이자 시드 범위 한정이다
WHERE memory_id <= 290000 AND title LIKE '여정 수정%';

-- ── 3. 검증: 전부 시드 원본 수치와 일치해야 한다 ─────────────
SELECT
    (SELECT COUNT(*) FROM users)            AS users,          -- 5,000
    (SELECT COUNT(*) FROM maps)             AS maps,           -- 5,000
    (SELECT COUNT(*) FROM map_members)      AS map_members,    -- 14,000
    (SELECT COUNT(*) FROM memories)         AS memories,       -- 290,000
    (SELECT COUNT(*) FROM media_files)      AS media_files,    -- 1,160,000
    (SELECT COUNT(*) FROM friendships)      AS friendships,    -- 25,000
    (SELECT COUNT(*) FROM file_cleanup_task) AS cleanup_tasks; -- 0

-- 수정 부하 흔적이 남았는지
SELECT COUNT(*) AS edited_left FROM memories WHERE title LIKE '여정%'; -- 0

-- 버퍼풀 대비 데이터 배율 — 라운드마다 기록한다
SELECT ROUND(@@innodb_buffer_pool_size/1024/1024, 1) AS pool_mb,
       ROUND(SUM(data_length+index_length)/1024/1024, 1) AS db_mb,
       ROUND(SUM(data_length+index_length)/@@innodb_buffer_pool_size, 2) AS ratio
FROM information_schema.tables WHERE table_schema = DATABASE();
