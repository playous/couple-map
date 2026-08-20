-- =============================================================
-- Vestige 부하테스트 시드 데이터 (v3 — 사용자 5,000명)
-- =============================================================
-- 실행 환경 : MySQL Workbench (dev 프로파일 DB)
-- 실행 방법 : 전체 선택 후 실행 (Ctrl+Shift+Enter)
-- 소요 시간 : 약 5~10분
--
-- v2 → v3 변경:
--   users 1,000 → 5,000 / maps 2,000 → 5,000
--   memories 150,000 → 290,000 / media_files 600,000 → 1,160,000
--   이유: VU 5,000으로 여정 부하를 걸 때 조회 계정이 500개뿐이면
--   VU 10개가 같은 지도를 공유한다. 작업 집합이 작아 버퍼풀에 통째로
--   올라가고 캐시 히트율이 비현실적으로 높아져 인덱스 개선이 측정되지 않는다.
--   file_url 컬럼 제거 반영 (presigned 전환, PR #116).
--
-- 생성 데이터:
--   users            5,000명  (providerId: test1 ~ test5000)
--   maps             5,000개  (user i 가 map i 의 OWNER)
--   map_members     14,000행  (OWNER 5,000 + EDITOR 5,000 + PENDING 4,000)
--   memories       290,000개  (지도 1~200: 500개씩 / 지도 201~4,000: 50개씩)
--   media_files  1,160,000개  (모든 추억에 IMAGE x3 + AUDIO x1)
--   friendships     25,000건  (유저당 5건 발신)
--
-- 계정 배정 (k6/lib/accounts.js와 연동 — 바꾸면 반드시 같이 바꿀 것):
--   조회      user 1     ~ 4,000   map 1     ~ 4,000  (추억 있음)
--   쓰기      user 4,001 ~ 4,700   map 4,001 ~ 4,700  (빈 지도)
--   업로드    user 4,701 ~ 4,900   map 4,701 ~ 4,900  (빈 지도)
--   지도생성  user 4,901 ~ 5,000
--
-- ID 규칙 (k6/helpers.js의 randomMemoryId와 연동):
--   지도 N(1~200)     : memory_id (N-1)x500 + 1  ~  Nx500
--   지도 N(201~4,000) : memory_id 100,000 + (N-201)x50 + 1  ~  +50
--   memory_date = '2023-01-01' + ((memory_id - 1) % 1095)일
--   category    = ELT((memory_id % 5) + 1, DATE,TRAVEL,FOOD,ANNIVERSARY,DAILY)
-- =============================================================

SET FOREIGN_KEY_CHECKS = 0;
SET UNIQUE_CHECKS = 0;
SET AUTOCOMMIT = 0;

-- =============================================================
-- 0. 기존 데이터 초기화
-- =============================================================
TRUNCATE TABLE file_cleanup_task;
TRUNCATE TABLE media_files;
TRUNCATE TABLE memories;
TRUNCATE TABLE map_members;
TRUNCATE TABLE friendships;
TRUNCATE TABLE maps;
TRUNCATE TABLE users;

-- =============================================================
-- 1. 숫자 테이블 (1 ~ 300,000) — 모든 INSERT...SELECT의 원천
-- =============================================================
SET SESSION cte_max_recursion_depth = 300001;

DROP TEMPORARY TABLE IF EXISTS seq;
CREATE TEMPORARY TABLE seq (n INT UNSIGNED PRIMARY KEY);

INSERT INTO seq
WITH RECURSIVE s(n) AS (
    SELECT 1
    UNION ALL
    SELECT n + 1 FROM s WHERE n < 300000
)
SELECT n FROM s;

COMMIT;

-- =============================================================
-- 2. USERS (5,000명)
-- =============================================================
INSERT INTO users (user_id, role, email, name, nickname, login_type, provider_id, friend_code, created_at, updated_at)
SELECT n,
       'USER',
       CONCAT('test', n, '@test.com'),
       CONCAT('테스트유저', n),
       CONCAT('user', LPAD(n, 5, '0')),  -- nickname 컬럼이 10자 제한이라 'tester'(6자)+5자리는 넘친다
       'GOOGLE',
       CONCAT('test', n),
       CONCAT('T', LPAD(n, 6, '0')),
       NOW(), NOW()
FROM seq WHERE n <= 5000;

COMMIT;

-- =============================================================
-- 3. MAPS (5,000개) — user i 가 map i 의 OWNER
-- =============================================================
INSERT INTO maps (map_id, map_name, description, category, created_at, updated_at)
SELECT n,
       CONCAT('지도_', LPAD(n, 5, '0')),
       '부하테스트 지도',
       IF(n % 4 = 0, 'FAMILY', 'COUPLE'),
       NOW(), NOW()
FROM seq WHERE n <= 5000;

COMMIT;

-- =============================================================
-- 4. MAP_MEMBERS (14,000행)
-- =============================================================

-- OWNER: user i → map i
INSERT INTO map_members (map_id, user_id, inviter_id, map_member_role, created_at, updated_at)
SELECT n, n, NULL, 'OWNER', NOW(), NOW() FROM seq WHERE n <= 5000;

-- EDITOR: map i 에 파트너 user (i % 5000) + 1
INSERT INTO map_members (map_id, user_id, inviter_id, map_member_role, created_at, updated_at)
SELECT n, (n % 5000) + 1, n, 'EDITOR', NOW(), NOW() FROM seq WHERE n <= 5000;

-- PENDING: 조회 유저(1~4,000)가 받은 미수락 초대.
-- GET /api/map/invitations 가 빈 배열만 돌려주면 그 API는 아무것도 측정하지 못한다.
-- 대상 지도는 (i + 2000) 근방이라 위의 OWNER/EDITOR 배정과 겹치지 않는다.
INSERT INTO map_members (map_id, user_id, inviter_id, map_member_role, created_at, updated_at)
SELECT ((n + 1999) % 5000) + 1, n, ((n + 1999) % 5000) + 1, 'PENDING', NOW(), NOW()
FROM seq WHERE n <= 4000;

COMMIT;

-- =============================================================
-- 5. MEMORIES (290,000개)
--    지도 1~200     : 500개씩 (memory_id 1 ~ 100,000)      마커 조회가 무거운 케이스
--    지도 201~4,000 : 50개씩  (memory_id 100,001 ~ 290,000) 스크롤 page 0~4 가능
-- =============================================================

-- Phase 1: 헤비 지도 (1~200)
INSERT INTO memories (memory_id, map_id, user_id, title, content, place_name, address,
                      memory_date, latitude, longitude, category, created_at, updated_at)
SELECT n,
       ((n - 1) DIV 500) + 1,
       ((n - 1) DIV 500) + 1,
       CONCAT('추억 ', n),
       CONCAT('추억 내용입니다. (지도 ', ((n - 1) DIV 500) + 1, ')'),
       ELT((n % 10) + 1,
           '서울 강남구', '부산 해운대', '제주 서귀포', '인천 송도', '수원 화성',
           '대전 유성구', '대구 동성로', '광주 무등산', '강릉 경포대', '전주 한옥마을'),
       CONCAT(ELT((n % 10) + 1,
           '서울시 강남구 테헤란로', '부산시 해운대구 해운대해변로',
           '제주특별자치도 서귀포시 중문관광로', '인천시 연수구 송도대로',
           '경기도 수원시 팔달구 화성로', '대전시 유성구 대학로',
           '대구시 중구 동성로', '광주시 북구 무등로',
           '강원도 강릉시 해안로', '전라북도 전주시 완산구 기린대로'),
           ' ', n, '번길'),
       DATE_ADD('2023-01-01', INTERVAL ((n - 1) % 1095) DAY),
       ROUND(34.0 + (n % 45) * 0.1, 6),
       ROUND(126.0 + (n % 35) * 0.1, 6),
       ELT((n % 5) + 1, 'DATE', 'TRAVEL', 'FOOD', 'ANNIVERSARY', 'DAILY'),
       NOW(), NOW()
FROM seq WHERE n <= 100000;

COMMIT;

-- Phase 2: 라이트 지도 (201~4,000)
INSERT INTO memories (memory_id, map_id, user_id, title, content, place_name, address,
                      memory_date, latitude, longitude, category, created_at, updated_at)
SELECT 100000 + n,
       ((n - 1) DIV 50) + 201,
       ((n - 1) DIV 50) + 201,
       CONCAT('추억 ', 100000 + n),
       CONCAT('추억 내용입니다. (지도 ', ((n - 1) DIV 50) + 201, ')'),
       ELT(((100000 + n) % 10) + 1,
           '서울 강남구', '부산 해운대', '제주 서귀포', '인천 송도', '수원 화성',
           '대전 유성구', '대구 동성로', '광주 무등산', '강릉 경포대', '전주 한옥마을'),
       CONCAT(ELT(((100000 + n) % 10) + 1,
           '서울시 강남구 테헤란로', '부산시 해운대구 해운대해변로',
           '제주특별자치도 서귀포시 중문관광로', '인천시 연수구 송도대로',
           '경기도 수원시 팔달구 화성로', '대전시 유성구 대학로',
           '대구시 중구 동성로', '광주시 북구 무등로',
           '강원도 강릉시 해안로', '전라북도 전주시 완산구 기린대로'),
           ' ', 100000 + n, '번길'),
       DATE_ADD('2023-01-01', INTERVAL ((100000 + n - 1) % 1095) DAY),
       ROUND(34.0 + ((100000 + n) % 45) * 0.1, 6),
       ROUND(126.0 + ((100000 + n) % 35) * 0.1, 6),
       ELT(((100000 + n) % 5) + 1, 'DATE', 'TRAVEL', 'FOOD', 'ANNIVERSARY', 'DAILY'),
       NOW(), NOW()
FROM seq WHERE n <= 190000;

COMMIT;

-- =============================================================
-- 6. MEDIA_FILES (1,160,000개) — 추억당 IMAGE x3 + AUDIO x1
--    file_url 컬럼은 없다. 조회 시점에 file_key로 서명해서 내려준다.
-- =============================================================

-- IMAGE (display_order 1~3)
INSERT INTO media_files (memory_id, file_key, original_filename, media_file_type, file_size, display_order, created_at, updated_at)
SELECT m.n,
       CONCAT('memory/img_', LPAD(m.n, 6, '0'), '_', d.ord, '.jpg'),
       CONCAT('photo_', m.n, '_', d.ord, '.jpg'),
       'IMAGE', 1048576, d.ord, NOW(), NOW()
FROM seq m
JOIN (SELECT 1 AS ord UNION ALL SELECT 2 UNION ALL SELECT 3) d
WHERE m.n <= 290000;

COMMIT;

-- AUDIO (display_order 4)
INSERT INTO media_files (memory_id, file_key, original_filename, media_file_type, file_size, display_order, created_at, updated_at)
SELECT n,
       CONCAT('memory/aud_', LPAD(n, 6, '0'), '_4.mp3'),
       CONCAT('audio_', n, '_4.mp3'),
       'AUDIO', 3145728, 4, NOW(), NOW()
FROM seq WHERE n <= 290000;

COMMIT;

-- =============================================================
-- 7. FRIENDSHIPS (25,000건) — 유저당 5건 발신 (수신 포함 10명 친구)
-- =============================================================
INSERT INTO friendships (requester_id, receiver_id, status, friend_pair_key, created_at, updated_at)
SELECT i, j, 'ACCEPTED', CONCAT(LEAST(i, j), ':', GREATEST(i, j)), NOW(), NOW()
FROM (
    SELECT ((n - 1) DIV 5) + 1                                  AS i,
           ((((n - 1) DIV 5) + ((n - 1) % 5) + 1) % 5000) + 1   AS j
    FROM seq WHERE n <= 25000
) t;

COMMIT;

-- =============================================================
-- 8. 마무리
-- =============================================================
DROP TEMPORARY TABLE IF EXISTS seq;

SET FOREIGN_KEY_CHECKS = 1;
SET UNIQUE_CHECKS = 1;
SET AUTOCOMMIT = 1;

-- =============================================================
-- 검증 — 아래 수치와 정확히 일치해야 한다
-- =============================================================
SELECT
    (SELECT COUNT(*) FROM users)        AS users,         -- 5,000
    (SELECT COUNT(*) FROM maps)         AS maps,          -- 5,000
    (SELECT COUNT(*) FROM map_members)  AS map_members,   -- 14,000
    (SELECT COUNT(*) FROM memories)     AS memories,      -- 290,000
    (SELECT COUNT(*) FROM media_files)  AS media_files,   -- 1,160,000
    (SELECT COUNT(*) FROM friendships)  AS friendships;   -- 25,000

-- ID 규칙 스팟 체크 (k6/helpers.js의 randomMemoryId와 일치해야 한다)
SELECT
    (SELECT COUNT(*) FROM memories WHERE map_id = 1)    AS map1_cnt,     -- 500
    (SELECT COUNT(*) FROM memories WHERE map_id = 200)  AS map200_cnt,   -- 500
    (SELECT COUNT(*) FROM memories WHERE map_id = 201)  AS map201_cnt,   -- 50
    (SELECT COUNT(*) FROM memories WHERE map_id = 4000) AS map4000_cnt,  -- 50
    (SELECT MIN(memory_id) FROM memories WHERE map_id = 201)  AS map201_first, -- 100,001
    (SELECT COUNT(*) FROM memories WHERE map_id = 4001) AS map4001_cnt,  -- 0 (쓰기용 빈 지도)
    (SELECT memory_date FROM memories WHERE memory_id = 1)    AS mem1_date;   -- 2023-01-01

-- 초대 목록이 비어 있지 않은지 (GET /api/map/invitations 측정 대상)
SELECT COUNT(*) AS pending_invites FROM map_members WHERE map_member_role = 'PENDING'; -- 4,000

-- 버퍼풀 대비 데이터 배율 — 기록용이다. 이 값을 맞추려고 버퍼풀을 조정하지 않는다.
-- 1.0 미만이면 데이터가 전부 메모리에 올라가 인덱스 개선 폭이 작게 나올 수 있으니
-- 결과 해석 시 조건을 병기한다. 버퍼풀 크기 자체는 별도 튜닝 라운드의 대상이다.
SELECT ROUND(@@innodb_buffer_pool_size/1024/1024, 1) AS pool_mb,
       ROUND(SUM(data_length+index_length)/1024/1024, 1) AS db_mb,
       ROUND(SUM(data_length+index_length)/@@innodb_buffer_pool_size, 2) AS ratio
FROM information_schema.tables WHERE table_schema = DATABASE();
