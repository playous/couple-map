/**
 * 시드 데이터 기준 계정, 지도 배정.
 *
 * load-test-seed.sql (v3) 기준:
 *   users          5,000명  providerId = test1 ~ test5000
 *   maps           5,000개  user i 가 map i 의 OWNER
 *   memories     290,000개  map 1~200: 500개씩 / map 201~4,000: 50개씩
 *   media_files 1,160,000개
 *
 * 그룹을 나누는 이유:
 *   조회 그룹과 쓰기 그룹이 같은 지도를 쓰면 서로 데이터를 바꿔서
 *   측정 조건이 실행마다 달라진다. 지도를 분리해 간섭을 없앤다.
 *
 * 쓰기, 업로드 대상은 map 4,001 이상(추억이 0개인 빈 지도)을 쓴다.
 * 조회 대상 지도의 추억 수가 실행 중에 변하지 않게 하기 위해서다.
 *
 * 조회 계정을 4,000개로 늘린 이유:
 *   VU 5,000으로 여정 부하를 걸 때 계정이 500개뿐이면 VU 10개가 같은
 *   지도를 공유한다. 작업 집합이 작아 버퍼풀에 통째로 올라가고
 *   캐시 히트율이 비현실적으로 높아져 인덱스 개선이 측정되지 않는다.
 */

function env(name, def) {
  const v = __ENV[name];
  return v === undefined || v === '' ? Number(def) : Number(v);
}

export const RANGES = {
  // 조회: 추억이 미리 채워진 지도 (1~200은 500개씩, 201~4,000은 50개씩)
  read: {
    userStart: env('READ_USER_START', 1),
    count: env('READ_COUNT', 4000),
    mapStart: env('READ_MAP_START', 1),
  },
  // 쓰기: 빈 지도. teardown에서 생성분을 지운다.
  write: {
    userStart: env('WRITE_USER_START', 4001),
    count: env('WRITE_COUNT', 700),
    mapStart: env('WRITE_MAP_START', 4001),
  },
  // 업로드: 빈 지도. 실제 S3 객체가 생기므로 S3_KEY_PREFIX=test/ 필수.
  upload: {
    userStart: env('UPLOAD_USER_START', 4701),
    count: env('UPLOAD_COUNT', 200),
    mapStart: env('UPLOAD_MAP_START', 4701),
  },
  // 지도 생성: 지도를 새로 만들므로 고정 mapStart가 없다.
  // teardown에서 "테스트 중 생긴 지도"만 지우려고 계정을 따로 분리한다.
  mapCreate: {
    userStart: env('MAPC_USER_START', 4901),
    count: env('MAPC_COUNT', 100),
    mapStart: 0, // 사용하지 않음
  },
};

/** API 이름 → 계정 그룹 */
export function groupOf(api) {
  if (api === 'write') return 'write';
  if (api === 'upload') return 'upload';
  return 'read';
}

/** 그룹의 유저 번호 배열 (test{n} 의 n) */
export function userNumbers(range) {
  const nums = [];
  for (let i = 0; i < range.count; i++) nums.push(range.userStart + i);
  return nums;
}
