-- =============================================================
-- CoupleMap 부하테스트 시드 데이터
-- =============================================================
-- 실행 환경 : MySQL Workbench (dev 프로파일 DB)
-- 실행 방법 : 전체 선택 후 실행 (Ctrl+Shift+Enter)
-- 소요 시간 : 약 15~30분 (미디어 파일 160,000개 포함)
--
-- 생성 데이터:
--   users            1,000명  (providerId: test1 ~ test1000)
--   maps             2,000개  (COUPLE 1,500개 + FAMILY 500개)
--   map_members      5,000행  (유저당 COUPLE 3개 + FAMILY 2개)
--   memories        40,000개  (지도 1~100: 200개씩 / 지도 101~500: 50개씩)
--   media_files    160,000개  (모든 추억에 IMAGE×3 + AUDIO×1)
--   friendships      5,000건  (유저당 10명 친구)
-- =============================================================

SET FOREIGN_KEY_CHECKS = 0;
SET AUTOCOMMIT = 0;

-- =============================================================
-- 0. 기존 데이터 초기화 (TRUNCATE)
-- =============================================================
TRUNCATE TABLE file_cleanup_task;
TRUNCATE TABLE media_files;
TRUNCATE TABLE memories;
TRUNCATE TABLE map_members;
TRUNCATE TABLE friendships;
TRUNCATE TABLE maps;
TRUNCATE TABLE users;

-- =============================================================
-- 시드 데이터 삽입 (Stored Procedure)
-- =============================================================
DELIMITER $$

DROP PROCEDURE IF EXISTS seed_test_data$$

CREATE PROCEDURE seed_test_data()
BEGIN
    DECLARE i            INT DEFAULT 1;
    DECLARE j            INT DEFAULT 1;
    DECLARE k            INT DEFAULT 1;
    DECLARE m1           INT;
    DECLARE m2           INT;
    DECLARE m3           INT;
    DECLARE m4           INT;
    DECLARE map_owner_id INT;
    DECLARE base_map_id  BIGINT;
    DECLARE target_map   BIGINT;
    DECLARE mem_seq      INT DEFAULT 0;

    -- =========================================================
    -- 1. USERS (1,000명)
    -- =========================================================
    SET i = 1;
    WHILE i <= 1000 DO
        INSERT INTO users (
            role, email, name, nickname,
            login_type, provider_id, friend_code,
            created_at, updated_at
        ) VALUES (
            'USER',
            CONCAT('test', i, '@test.com'),
            CONCAT('테스트유저', i),
            CONCAT('tester', LPAD(i, 4, '0')),
            'GOOGLE',
            CONCAT('test', i),
            CONCAT('TC', LPAD(i, 6, '0')),
            NOW(), NOW()
        );
        SET i = i + 1;
    END WHILE;


    -- =========================================================
    -- 2. COUPLE MAPS (1,500개)
    -- =========================================================

    -- Round 1 (1,000개)
    SET i = 1;
    WHILE i <= 1000 DO
        INSERT INTO maps (map_name, description, category, created_at, updated_at)
        VALUES (CONCAT('커플지도_', LPAD(i, 4, '0')), '커플 추억 지도', 'COUPLE', NOW(), NOW());
        SET @cur_map = LAST_INSERT_ID();

        INSERT INTO map_members (map_id, user_id, inviter_id, map_member_role, created_at, updated_at)
        VALUES (@cur_map, i, NULL, 'OWNER', NOW(), NOW());
        INSERT INTO map_members (map_id, user_id, inviter_id, map_member_role, created_at, updated_at)
        VALUES (@cur_map, (i % 1000) + 1, i, 'EDITOR', NOW(), NOW());

        SET i = i + 1;
    END WHILE;

    -- Round 2 (500개)
    SET i = 1;
    WHILE i <= 500 DO
        INSERT INTO maps (map_name, description, category, created_at, updated_at)
        VALUES (CONCAT('커플여행지도_', LPAD(i, 4, '0')), '커플 여행 지도', 'COUPLE', NOW(), NOW());
        SET @cur_map = LAST_INSERT_ID();

        INSERT INTO map_members (map_id, user_id, inviter_id, map_member_role, created_at, updated_at)
        VALUES (@cur_map, i, NULL, 'OWNER', NOW(), NOW());
        INSERT INTO map_members (map_id, user_id, inviter_id, map_member_role, created_at, updated_at)
        VALUES (@cur_map, i + 500, i, 'EDITOR', NOW(), NOW());

        SET i = i + 1;
    END WHILE;


    -- =========================================================
    -- 3. FAMILY MAPS (500개)
    -- =========================================================

    -- Round 1 (250개)
    SET i = 0;
    WHILE i < 250 DO
        INSERT INTO maps (map_name, description, category, created_at, updated_at)
        VALUES (CONCAT('패밀리지도_', LPAD(i*4+1, 4, '0')), '가족 추억 지도', 'FAMILY', NOW(), NOW());
        SET @cur_map = LAST_INSERT_ID();

        INSERT INTO map_members (map_id, user_id, inviter_id, map_member_role, created_at, updated_at)
        VALUES (@cur_map, i*4+1, NULL,  'OWNER',  NOW(), NOW());
        INSERT INTO map_members (map_id, user_id, inviter_id, map_member_role, created_at, updated_at)
        VALUES (@cur_map, i*4+2, i*4+1, 'EDITOR', NOW(), NOW());
        INSERT INTO map_members (map_id, user_id, inviter_id, map_member_role, created_at, updated_at)
        VALUES (@cur_map, i*4+3, i*4+1, 'EDITOR', NOW(), NOW());
        INSERT INTO map_members (map_id, user_id, inviter_id, map_member_role, created_at, updated_at)
        VALUES (@cur_map, i*4+4, i*4+1, 'EDITOR', NOW(), NOW());

        SET i = i + 1;
    END WHILE;

    -- Round 2 (250개)
    SET i = 0;
    WHILE i < 250 DO
        SET m1 = i*4 + 3;
        SET m2 = i*4 + 4;
        SET m3 = ((i*4 + 4) % 1000) + 1;
        SET m4 = ((i*4 + 5) % 1000) + 1;

        INSERT INTO maps (map_name, description, category, created_at, updated_at)
        VALUES (CONCAT('패밀리여행지도_', LPAD(m1, 4, '0')), '가족 여행 지도', 'FAMILY', NOW(), NOW());
        SET @cur_map = LAST_INSERT_ID();

        INSERT INTO map_members (map_id, user_id, inviter_id, map_member_role, created_at, updated_at)
        VALUES (@cur_map, m1, NULL, 'OWNER',  NOW(), NOW());
        INSERT INTO map_members (map_id, user_id, inviter_id, map_member_role, created_at, updated_at)
        VALUES (@cur_map, m2, m1,   'EDITOR', NOW(), NOW());
        INSERT INTO map_members (map_id, user_id, inviter_id, map_member_role, created_at, updated_at)
        VALUES (@cur_map, m3, m1,   'EDITOR', NOW(), NOW());
        INSERT INTO map_members (map_id, user_id, inviter_id, map_member_role, created_at, updated_at)
        VALUES (@cur_map, m4, m1,   'EDITOR', NOW(), NOW());

        SET i = i + 1;
    END WHILE;


    -- =========================================================
    -- 4. MEMORIES + MEDIA FILES
    --
    --    지도 1~100   : 200개씩 (총 20,000개)
    --    지도 101~500 : 50개씩  (총 20,000개)
    --    전체         : 40,000개
    --
    --    각 추억마다 미디어 파일 4개 즉시 삽입
    --      display_order 1,2,3 → IMAGE (1MB)
    --      display_order 4     → AUDIO (3MB)
    -- =========================================================
    SELECT MIN(map_id) INTO base_map_id FROM maps;

    -- ── Phase 1: 지도 1~100, 200개씩 ────────────────────────
    SET i = 0;
    WHILE i < 100 DO
        SET target_map = base_map_id + i;

        SELECT user_id INTO map_owner_id
        FROM map_members
        WHERE map_id = target_map AND map_member_role = 'OWNER'
        LIMIT 1;

        SET j = 1;
        WHILE j <= 200 DO
            SET mem_seq = mem_seq + 1;

            INSERT INTO memories (
                map_id, user_id,
                title, content,
                place_name, address,
                memory_date,
                latitude, longitude,
                category,
                created_at, updated_at
            ) VALUES (
                target_map,
                map_owner_id,
                CONCAT('추억 ', mem_seq),
                CONCAT('추억 내용입니다. (지도 ', i+1, ', 번호 ', j, ')'),
                ELT((mem_seq % 10) + 1,
                    '서울 강남구', '부산 해운대', '제주 서귀포', '인천 송도', '수원 화성',
                    '대전 유성구', '대구 동성로', '광주 무등산', '강릉 경포대', '전주 한옥마을'),
                CONCAT(ELT((mem_seq % 10) + 1,
                    '서울시 강남구 테헤란로', '부산시 해운대구 해운대해변로',
                    '제주특별자치도 서귀포시 중문관광로', '인천시 연수구 송도대로',
                    '경기도 수원시 팔달구 화성로', '대전시 유성구 대학로',
                    '대구시 중구 동성로', '광주시 북구 무등로',
                    '강원도 강릉시 해안로', '전라북도 전주시 완산구 기린대로'),
                    ' ', mem_seq, '번길'),
                DATE_ADD('2023-01-01', INTERVAL ((mem_seq - 1) % 1095) DAY),
                ROUND(34.0 + (mem_seq % 45) * 0.1, 6),
                ROUND(126.0 + (mem_seq % 35) * 0.1, 6),
                ELT((mem_seq % 5) + 1, 'DATE', 'TRAVEL', 'FOOD', 'ANNIVERSARY', 'DAILY'),
                NOW(), NOW()
            );
            SET @cur_mem = LAST_INSERT_ID();

            INSERT INTO media_files (memory_id, file_url, file_key, original_filename, media_file_type, file_size, display_order, created_at, updated_at)
            VALUES (@cur_mem, CONCAT('https://couplemap-bucket.s3.ap-northeast-2.amazonaws.com/memory/img_', LPAD(mem_seq, 6, '0'), '_1.jpg'),
                    CONCAT('memory/img_', LPAD(mem_seq, 6, '0'), '_1.jpg'), CONCAT('photo_', mem_seq, '_1.jpg'), 'IMAGE', 1048576, 1, NOW(), NOW());
            INSERT INTO media_files (memory_id, file_url, file_key, original_filename, media_file_type, file_size, display_order, created_at, updated_at)
            VALUES (@cur_mem, CONCAT('https://couplemap-bucket.s3.ap-northeast-2.amazonaws.com/memory/img_', LPAD(mem_seq, 6, '0'), '_2.jpg'),
                    CONCAT('memory/img_', LPAD(mem_seq, 6, '0'), '_2.jpg'), CONCAT('photo_', mem_seq, '_2.jpg'), 'IMAGE', 1048576, 2, NOW(), NOW());
            INSERT INTO media_files (memory_id, file_url, file_key, original_filename, media_file_type, file_size, display_order, created_at, updated_at)
            VALUES (@cur_mem, CONCAT('https://couplemap-bucket.s3.ap-northeast-2.amazonaws.com/memory/img_', LPAD(mem_seq, 6, '0'), '_3.jpg'),
                    CONCAT('memory/img_', LPAD(mem_seq, 6, '0'), '_3.jpg'), CONCAT('photo_', mem_seq, '_3.jpg'), 'IMAGE', 1048576, 3, NOW(), NOW());
            INSERT INTO media_files (memory_id, file_url, file_key, original_filename, media_file_type, file_size, display_order, created_at, updated_at)
            VALUES (@cur_mem, CONCAT('https://couplemap-bucket.s3.ap-northeast-2.amazonaws.com/memory/aud_', LPAD(mem_seq, 6, '0'), '_4.mp3'),
                    CONCAT('memory/aud_', LPAD(mem_seq, 6, '0'), '_4.mp3'), CONCAT('audio_', mem_seq, '_4.mp3'), 'AUDIO', 3145728, 4, NOW(), NOW());

            SET j = j + 1;
        END WHILE;
        SET i = i + 1;
    END WHILE;

    -- ── Phase 2: 지도 101~500, 50개씩 ───────────────────────
    SET i = 100;
    WHILE i < 500 DO
        SET target_map = base_map_id + i;

        SELECT user_id INTO map_owner_id
        FROM map_members
        WHERE map_id = target_map AND map_member_role = 'OWNER'
        LIMIT 1;

        SET j = 1;
        WHILE j <= 50 DO
            SET mem_seq = mem_seq + 1;

            INSERT INTO memories (
                map_id, user_id,
                title, content,
                place_name, address,
                memory_date,
                latitude, longitude,
                category,
                created_at, updated_at
            ) VALUES (
                target_map,
                map_owner_id,
                CONCAT('추억 ', mem_seq),
                CONCAT('추억 내용입니다. (지도 ', i+1, ', 번호 ', j, ')'),
                ELT((mem_seq % 10) + 1,
                    '서울 강남구', '부산 해운대', '제주 서귀포', '인천 송도', '수원 화성',
                    '대전 유성구', '대구 동성로', '광주 무등산', '강릉 경포대', '전주 한옥마을'),
                CONCAT(ELT((mem_seq % 10) + 1,
                    '서울시 강남구 테헤란로', '부산시 해운대구 해운대해변로',
                    '제주특별자치도 서귀포시 중문관광로', '인천시 연수구 송도대로',
                    '경기도 수원시 팔달구 화성로', '대전시 유성구 대학로',
                    '대구시 중구 동성로', '광주시 북구 무등로',
                    '강원도 강릉시 해안로', '전라북도 전주시 완산구 기린대로'),
                    ' ', mem_seq, '번길'),
                DATE_ADD('2023-01-01', INTERVAL ((mem_seq - 1) % 1095) DAY),
                ROUND(34.0 + (mem_seq % 45) * 0.1, 6),
                ROUND(126.0 + (mem_seq % 35) * 0.1, 6),
                ELT((mem_seq % 5) + 1, 'DATE', 'TRAVEL', 'FOOD', 'ANNIVERSARY', 'DAILY'),
                NOW(), NOW()
            );
            SET @cur_mem = LAST_INSERT_ID();

            INSERT INTO media_files (memory_id, file_url, file_key, original_filename, media_file_type, file_size, display_order, created_at, updated_at)
            VALUES (@cur_mem, CONCAT('https://couplemap-bucket.s3.ap-northeast-2.amazonaws.com/memory/img_', LPAD(mem_seq, 6, '0'), '_1.jpg'),
                    CONCAT('memory/img_', LPAD(mem_seq, 6, '0'), '_1.jpg'), CONCAT('photo_', mem_seq, '_1.jpg'), 'IMAGE', 1048576, 1, NOW(), NOW());
            INSERT INTO media_files (memory_id, file_url, file_key, original_filename, media_file_type, file_size, display_order, created_at, updated_at)
            VALUES (@cur_mem, CONCAT('https://couplemap-bucket.s3.ap-northeast-2.amazonaws.com/memory/img_', LPAD(mem_seq, 6, '0'), '_2.jpg'),
                    CONCAT('memory/img_', LPAD(mem_seq, 6, '0'), '_2.jpg'), CONCAT('photo_', mem_seq, '_2.jpg'), 'IMAGE', 1048576, 2, NOW(), NOW());
            INSERT INTO media_files (memory_id, file_url, file_key, original_filename, media_file_type, file_size, display_order, created_at, updated_at)
            VALUES (@cur_mem, CONCAT('https://couplemap-bucket.s3.ap-northeast-2.amazonaws.com/memory/img_', LPAD(mem_seq, 6, '0'), '_3.jpg'),
                    CONCAT('memory/img_', LPAD(mem_seq, 6, '0'), '_3.jpg'), CONCAT('photo_', mem_seq, '_3.jpg'), 'IMAGE', 1048576, 3, NOW(), NOW());
            INSERT INTO media_files (memory_id, file_url, file_key, original_filename, media_file_type, file_size, display_order, created_at, updated_at)
            VALUES (@cur_mem, CONCAT('https://couplemap-bucket.s3.ap-northeast-2.amazonaws.com/memory/aud_', LPAD(mem_seq, 6, '0'), '_4.mp3'),
                    CONCAT('memory/aud_', LPAD(mem_seq, 6, '0'), '_4.mp3'), CONCAT('audio_', mem_seq, '_4.mp3'), 'AUDIO', 3145728, 4, NOW(), NOW());

            SET j = j + 1;
        END WHILE;
        SET i = i + 1;
    END WHILE;


    -- =========================================================
    -- 5. FRIENDSHIPS (5,000건)
    -- =========================================================
    SET i = 1;
    WHILE i <= 1000 DO
        SET k = 1;
        WHILE k <= 5 DO
            SET j = ((i - 1 + k) % 1000) + 1;

            INSERT INTO friendships (
                requester_id, receiver_id,
                status, friend_pair_key,
                created_at, updated_at
            ) VALUES (
                i, j,
                'ACCEPTED',
                CONCAT(LEAST(i, j), ':', GREATEST(i, j)),
                NOW(), NOW()
            );
            SET k = k + 1;
        END WHILE;
        SET i = i + 1;
    END WHILE;

END$$

DELIMITER ;

CALL seed_test_data();
DROP PROCEDURE IF EXISTS seed_test_data;

COMMIT;
SET FOREIGN_KEY_CHECKS = 1;
SET AUTOCOMMIT = 1;

-- =============================================================
-- 검증 쿼리 (실행 후 아래 주석 해제해서 확인)
-- =============================================================
-- SELECT COUNT(*) AS users        FROM users;           -- 1,000
-- SELECT COUNT(*) AS maps         FROM maps;            -- 2,000
-- SELECT COUNT(*) AS map_members  FROM map_members;     -- 5,000
-- SELECT COUNT(*) AS memories     FROM memories;        -- 40,000
-- SELECT COUNT(*) AS media_files  FROM media_files;     -- 160,000
-- SELECT COUNT(*) AS friendships  FROM friendships;     -- 5,000
