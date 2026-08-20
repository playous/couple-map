-- =============================================================
-- 부하 테스트 DB 상태 스냅샷 (Workbench에서 실행)
-- =============================================================
-- 언제 실행하나:
--   ① 라운드 시작 전 (부하 테스트 직전)
--   ② 라운드 종료 후 (부하 테스트 직후)
--   → 두 결과의 차이(델타)가 그 라운드의 실제 디스크 I/O량이다.
--
-- 왜 필요한가:
--   시드 v2(15만/60만 행)의 목적은 "데이터를 버퍼풀보다 크게 만들어
--   디스크 I/O가 발생하는 구간에서 측정하는 것"이다.
--   그런데 innodb_buffer_pool_size는 로컬 MySQL 설정이라 git 밖에 있다.
--   이 값이 바뀌면 모든 라운드 비교가 무효가 되므로 매 라운드 기록한다.
--
-- 2026-08-12 기준 실측: 버퍼풀 128MB / DB 199MB (1.6배) / 최근 히트율 57.5%
-- =============================================================

-- ── 1. 버퍼풀 설정과 점유 상태 ────────────────────────────────
-- pool_mb        : 버퍼풀 총 크기 (이 값이 라운드마다 같아야 한다)
-- used_mb        : 실제 데이터 페이지가 차지한 양
-- free_mb        : 여유. 0에 가까우면 캐시 경쟁 중이라는 뜻
-- hit_rate_1000  : 최근 구간 히트율 (1000분율). 575 = 57.5%
--                  ★ 누적 히트율(아래 3번)과 완전히 다른 값이다. 이쪽이 현재 상태.
SELECT
    ROUND(POOL_SIZE * @@innodb_page_size / 1024 / 1024, 1)     AS pool_mb,
    ROUND(DATABASE_PAGES * @@innodb_page_size / 1024 / 1024, 1) AS used_mb,
    ROUND(FREE_BUFFERS * @@innodb_page_size / 1024 / 1024, 1)   AS free_mb,
    HIT_RATE                                                    AS hit_rate_1000,
    PAGES_READ_RATE                                             AS pages_read_per_sec,
    NUMBER_PAGES_READ                                           AS pages_read_total
FROM information_schema.INNODB_BUFFER_POOL_STATS;

-- ── 2. DB 크기 vs 버퍼풀 (배율이 핵심) ────────────────────────
-- ratio가 1.0 미만이면 전부 메모리에 올라가므로 인덱스 개선 효과가 안 보인다.
-- 1.5~2.0 구간이 측정에 적당하다. R2에서 인덱스를 추가하면 이 값이 커진다.
SELECT
    ROUND(SUM(data_length + index_length) / 1024 / 1024, 1) AS db_total_mb,
    ROUND(SUM(data_length) / 1024 / 1024, 1)                AS data_mb,
    ROUND(SUM(index_length) / 1024 / 1024, 1)               AS index_mb,
    ROUND(@@innodb_buffer_pool_size / 1024 / 1024, 1)       AS pool_mb,
    ROUND(SUM(data_length + index_length) / @@innodb_buffer_pool_size, 2) AS ratio_db_over_pool
FROM information_schema.tables
WHERE table_schema = 'couplemap';

-- ── 3. 디스크 읽기 누적 카운터 ────────────────────────────────
-- ★ 이 값들은 서버 시작 이후 누적이며 FLUSH STATUS로 리셋되지 않는다.
--   따라서 "라운드 전 값"과 "라운드 후 값"을 빼서 델타를 봐야 한다.
--   disk_reads 델타 = 그 라운드에서 실제로 디스크를 읽은 페이지 수
--   델타 × 16KB = 그 라운드의 디스크 읽기량
SELECT
    (SELECT VARIABLE_VALUE FROM performance_schema.global_status
      WHERE VARIABLE_NAME = 'Innodb_buffer_pool_read_requests')        AS logical_reads_total,
    (SELECT VARIABLE_VALUE FROM performance_schema.global_status
      WHERE VARIABLE_NAME = 'Innodb_buffer_pool_reads')                AS disk_reads_total,
    (SELECT VARIABLE_VALUE FROM performance_schema.global_status
      WHERE VARIABLE_NAME = 'Innodb_data_read')                        AS bytes_read_total,
    (SELECT VARIABLE_VALUE FROM performance_schema.global_status
      WHERE VARIABLE_NAME = 'Innodb_rows_read')                        AS rows_read_total,
    ROUND(100 * (1 -
        (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME='Innodb_buffer_pool_reads')
      / (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME='Innodb_buffer_pool_read_requests')
    ), 3) AS cumulative_hit_pct;

-- ── 4. 테이블별 크기 ──────────────────────────────────────────
SELECT table_name,
       table_rows,
       ROUND(data_length / 1024 / 1024, 1)                 AS data_mb,
       ROUND(index_length / 1024 / 1024, 1)                AS index_mb,
       ROUND((data_length + index_length) / 1024 / 1024, 1) AS total_mb
FROM information_schema.tables
WHERE table_schema = 'couplemap'
ORDER BY (data_length + index_length) DESC;

-- ── 5. 인덱스별 크기 (R2 전/후 비교용) ────────────────────────
-- PRIMARY는 클러스터드 인덱스 = 테이블 데이터 자체다.
-- R2에서 인덱스를 추가하면 여기에 새 행이 생기고 index_mb 합계가 늘어난다.
-- 2026-08-12 실측: media_files PRIMARY 116.66 / FK 21.55, memories PRIMARY 45.58 / FK 6.52×2
SELECT table_name,
       index_name,
       ROUND(stat_value * @@innodb_page_size / 1024 / 1024, 2) AS size_mb
FROM mysql.innodb_index_stats
WHERE database_name = 'couplemap' AND stat_name = 'size'
ORDER BY stat_value DESC;

-- ── 6. 버퍼풀에 어느 테이블이 올라와 있는가 ───────────────────
-- 캐시 경쟁의 실체. media_files가 버퍼풀을 독점하면 memories 조회가
-- 매번 디스크를 타게 된다. R2 커버링 인덱스의 목표가 바로 이 구도 변경.
-- (버퍼풀 전체를 스캔하므로 수백 ms 걸린다. 부하 측정 중에는 실행하지 말 것)
SELECT
    IFNULL(TABLE_NAME, 'unallocated/system')                AS table_name,
    COUNT(*)                                                AS pages,
    ROUND(COUNT(*) * @@innodb_page_size / 1024 / 1024, 1)   AS mb,
    ROUND(100 * COUNT(*) / (SELECT POOL_SIZE FROM information_schema.INNODB_BUFFER_POOL_STATS), 1) AS pct_of_pool
FROM information_schema.INNODB_BUFFER_PAGE
GROUP BY TABLE_NAME
ORDER BY pages DESC
LIMIT 12;

-- =============================================================
-- 기록 양식 (라운드 표에 함께 남길 것)
-- =============================================================
-- 라운드: R?         시각: ____
-- 버퍼풀: ___MB   DB: ___MB   배율: ___배   여유: ___MB
-- 라운드 전 disk_reads: ______    라운드 후: ______    델타: ______ (×16KB = ___MB)
-- 최근 히트율(HIT_RATE): ___/1000
-- =============================================================
