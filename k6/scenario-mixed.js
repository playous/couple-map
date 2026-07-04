/**
 * 시나리오 4 — 최종 혼합 부하
 *
 * 목적  : 조회 + 쓰기 + 업로드가 동시에 발생할 때의 실제 병목 재현
 *         → 모든 개선이 끝난 후 목표 달성 여부 최종 검증에도 사용
 *
 * 사용자 그룹 (TOTAL_VUS=1000 기준):
 *   read_group   588명 (60%) : 추억 목록 + 마커 조회
 *   detail_group 196명 (20%) : 추억 상세 + 캘린더 조회
 *   browse_group  98명 (10%) : 지도 + 유저 정보 조회
 *   write_group   74명 (7.5%): 텍스트 추억 생성
 *   upload_group  24명 (2.5%): JPEG×3 + MP3×1 업로드 추억 생성
 *   map_group     10명 (고정): 지도 생성 + teardown 정리
 *   edit_group    10명 (고정): 기존 추억 텍스트 수정
 *
 * 실행  :
 *   k6 run --env BASE_URL=http://localhost:8080 \
 *           --env TOTAL_VUS=1000 \
 *           k6/scenario-mixed.js
 *
 * TOTAL_VUS : 200 | 300 | 500 | 1000
 *
 * 계정 배정:
 *   읽기/상세/탐색 VU : test1..test500   (읽기 지도 map 1..500 사용)
 *   쓰기 VU           : test501..test574  (map 501..574)
 *   업로드 VU         : test575..test598  (map 575..598)
 *   지도생성 VU       : test601..test610
 *   수정 VU           : test1..test100    (map 1..100, 본인 추억 수정)
 */
import http from 'k6/http';
import { check, sleep } from 'k6';
import {
  BASE_URL, fetchTokensBatch, authHeaders,
  READ_MAP_IDS, randomMemoryId, randomInt,
  makeDummyJpeg, makeDummyMp3, memoryRequestBlob, buildMultipart,
} from './helpers.js';

const TOTAL_VUS   = parseInt(__ENV.TOTAL_VUS || '1000');
const MAP_VUS     = 10;
const EDIT_VUS    = 10;
const FLEX_VUS    = TOTAL_VUS - MAP_VUS - EDIT_VUS;
const READ_VUS    = Math.round(FLEX_VUS * 0.60);
const DETAIL_VUS  = Math.round(FLEX_VUS * 0.20);
const BROWSE_VUS  = Math.round(FLEX_VUS * 0.10);
const WRITE_VUS   = Math.round(FLEX_VUS * 0.075);
const UPLOAD_VUS  = FLEX_VUS - READ_VUS - DETAIL_VUS - BROWSE_VUS - WRITE_VUS;

// 토큰 인덱스 오프셋
const WRITE_TOKEN_OFFSET  = 500;
const UPLOAD_TOKEN_OFFSET = 500 + WRITE_VUS;
const MAP_TOKEN_OFFSET    = 500 + WRITE_VUS + UPLOAD_VUS;

// 계정별 전용 지도 시작 ID
const WRITE_MAP_START  = 501;
const UPLOAD_MAP_START = 501 + WRITE_VUS;  // 575
const MAP_USER_START   = 601;

const RAMP_STAGES = [
  { duration: '30s', target: Math.floor(TOTAL_VUS * 0.1) },
  { duration: '30s', target: TOTAL_VUS },
  { duration: '3m',  target: TOTAL_VUS },
  { duration: '1m',  target: 0 },
];

export const options = {
  teardownTimeout: '10m',
  scenarios: {
    read_group: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages:   RAMP_STAGES.map(s => ({ ...s, target: Math.round(s.target * (READ_VUS / TOTAL_VUS)) })),
      exec:     'readFunc',
    },
    detail_group: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages:   RAMP_STAGES.map(s => ({ ...s, target: Math.round(s.target * (DETAIL_VUS / TOTAL_VUS)) })),
      exec:     'detailFunc',
    },
    browse_group: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages:   RAMP_STAGES.map(s => ({ ...s, target: Math.round(s.target * (BROWSE_VUS / TOTAL_VUS)) })),
      exec:     'browseFunc',
    },
    write_group: {
      executor:  'constant-vus',
      vus:       WRITE_VUS,
      duration:  '4m30s',
      startTime: '30s',
      exec:      'writeFunc',
    },
    upload_group: {
      executor:  'constant-vus',
      vus:       UPLOAD_VUS,
      duration:  '4m30s',
      startTime: '30s',
      exec:      'uploadFunc',
    },
    map_group: {
      executor:  'constant-vus',
      vus:       MAP_VUS,
      duration:  '4m30s',
      startTime: '30s',
      exec:      'mapFunc',
    },
    edit_group: {
      executor:  'constant-vus',
      vus:       EDIT_VUS,
      duration:  '4m30s',
      startTime: '30s',
      exec:      'editFunc',
    },
  },
  thresholds: {
    // 조회 p95 < 100ms
    'http_req_duration{name:GET_memory_list}':   ['p(95)<100'],
    'http_req_duration{name:GET_markers}':        ['p(95)<100'],
    'http_req_duration{name:GET_memory_detail}':  ['p(95)<100'],
    'http_req_duration{name:GET_map_detail}':     ['p(95)<100'],
    'http_req_duration{name:GET_calendar}':       ['p(95)<100'],
    // 일반 쓰기 p95 < 300ms
    'http_req_duration{name:POST_memory_text}':   ['p(95)<300'],
    // 업로드 p95 < 500ms
    'http_req_duration{name:POST_memory_upload}': ['p(95)<500'],
    // 지도 생성 p95 < 300ms
    'http_req_duration{name:POST_map}':           ['p(95)<300'],
    // 추억 수정 p95 < 300ms
    'http_req_duration{name:PUT_memory}':         ['p(95)<300'],
    // 전체 오류율 < 1%
    http_req_failed: ['rate<0.01'],
    // 전체 RPS > 100
    http_reqs: ['rate>100'],
  },
};

export function setup() {
  const tokens = fetchTokensBatch([
    ...Array.from({ length: 500 },      (_, i) => i + 1),                // 1~500        → tokens[0..499]
    ...Array.from({ length: WRITE_VUS }, (_, i) => i + WRITE_MAP_START),  // 501~574      → tokens[500..573]
    ...Array.from({ length: UPLOAD_VUS },(_, i) => i + UPLOAD_MAP_START), // 575~598      → tokens[574..597]
    ...Array.from({ length: MAP_VUS },   (_, i) => i + MAP_USER_START),   // 601~610      → tokens[598..607]
  ]);

  // 지도생성 계정의 테스트 전 맵 ID 스냅샷 (teardown에서 신규 생성분만 삭제)
  const mapSnapshots = {};
  for (let i = 0; i < MAP_VUS; i++) {
    const token = tokens[MAP_TOKEN_OFFSET + i];
    const res = http.get(`${BASE_URL}/api/map`, { headers: authHeaders(token) });
    if (res.status === 200) {
      mapSnapshots[MAP_USER_START + i] = JSON.parse(res.body).data.map(m => m.mapId);
    } else {
      mapSnapshots[MAP_USER_START + i] = [];
    }
  }

  return { tokens, mapSnapshots };
}

// ── 일반 조회: 추억 목록 + 마커 ─────────────────────────────
export function readFunc({ tokens }) {
  const idx   = (__VU - 1) % 500;
  const token = tokens[idx];
  const mapId = READ_MAP_IDS[idx % READ_MAP_IDS.length];
  const h     = authHeaders(token);

  if (Math.random() < 0.6) {
    const res = http.get(
      `${BASE_URL}/api/maps/${mapId}/memories?page=${randomInt(0, 4)}&size=10`,
      { headers: h, tags: { name: 'GET_memory_list' } }
    );
    check(res, { '목록 200': r => r.status === 200 });
  } else {
    const res = http.get(
      `${BASE_URL}/api/maps/${mapId}/memories/markers`,
      { headers: h, tags: { name: 'GET_markers' } }
    );
    check(res, { '마커 200': r => r.status === 200 });
  }
  sleep(randomInt(5, 20) / 10);
}

// ── 상세 조회: 추억 상세 + 캘린더 ──────────────────────────
export function detailFunc({ tokens }) {
  const idx   = (__VU - 1) % 500;
  const token = tokens[idx];
  const mapId = READ_MAP_IDS[idx % READ_MAP_IDS.length];
  const h     = authHeaders(token);

  if (Math.random() < 0.8) {
    const res = http.get(
      `${BASE_URL}/api/maps/${mapId}/memories/${randomMemoryId(mapId)}`,
      { headers: h, tags: { name: 'GET_memory_detail' } }
    );
    check(res, { '상세 200': r => r.status === 200 });
  } else {
    const res = http.get(
      `${BASE_URL}/api/calendar/memories?year=2024`,
      { headers: h, tags: { name: 'GET_calendar' } }
    );
    check(res, { '캘린더 200': r => r.status === 200 });
  }
  sleep(randomInt(5, 20) / 10);
}

// ── 탐색: 지도 + 유저 정보 ──────────────────────────────────
export function browseFunc({ tokens }) {
  const idx   = (__VU - 1) % 500;
  const token = tokens[idx];
  const mapId = READ_MAP_IDS[idx % READ_MAP_IDS.length];
  const h     = authHeaders(token);

  if (Math.random() < 0.5) {
    const res = http.get(
      `${BASE_URL}/api/map/${mapId}`,
      { headers: h, tags: { name: 'GET_map_detail' } }
    );
    check(res, { '지도 200': r => r.status === 200 });
  } else {
    const res = http.get(
      `${BASE_URL}/api/users/me`,
      { headers: h, tags: { name: 'GET_user_me' } }
    );
    check(res, { '유저 200': r => r.status === 200 });
  }
  sleep(randomInt(5, 20) / 10);
}

// ── 텍스트 쓰기 (사진 없음) ─────────────────────────────────
export function writeFunc({ tokens }) {
  const vuIdx = (__VU - 1) % WRITE_VUS;
  const token = tokens[WRITE_TOKEN_OFFSET + vuIdx];
  const mapId = WRITE_MAP_START + vuIdx;
  const h     = authHeaders(token);

  const res = http.post(
    `${BASE_URL}/api/maps/${mapId}/memories`,
    { request: memoryRequestBlob({
        title:      `쓰기 테스트 VU${__VU} #${__ITER}`,
        content:    '텍스트만 있는 추억',
        placeName:  '서울 강남구',
        address:    '서울시 강남구 테헤란로 123',
        memoryDate: '2025-06-15',
        latitude:   37.5665,
        longitude:  126.9780,
        category:   'DAILY',
      }),
    },
    { headers: h, tags: { name: 'POST_memory_text' } }
  );

  check(res, { '쓰기 201': r => r.status === 201 });
  sleep(randomInt(10, 30) / 10);
}

// ── 사진(×3) + 오디오(×1) 업로드 ───────────────────────────
export function uploadFunc({ tokens }) {
  const vuIdx = (__VU - 1) % UPLOAD_VUS;
  const token = tokens[UPLOAD_TOKEN_OFFSET + vuIdx];
  const mapId = UPLOAD_MAP_START + vuIdx;
  const h     = authHeaders(token);

  const requestJson = JSON.stringify({
    title:      `업로드 VU${__VU} #${__ITER}`,
    content:    'JPEG×3 + MP3×1 업로드 추억',
    placeName:  '부산 해운대',
    address:    '부산시 해운대구 해운대해변로 264',
    memoryDate: '2025-06-20',
    latitude:   35.1587,
    longitude:  129.1604,
    category:   'TRAVEL',
  });
  const { body, contentType } = buildMultipart([
    { name: 'request', filename: 'request',   type: 'application/json', data: requestJson },
    { name: 'files',   filename: 'photo1.jpg', type: 'image/jpeg',      data: makeDummyJpeg() },
    { name: 'files',   filename: 'photo2.jpg', type: 'image/jpeg',      data: makeDummyJpeg() },
    { name: 'files',   filename: 'photo3.jpg', type: 'image/jpeg',      data: makeDummyJpeg() },
    { name: 'files',   filename: 'audio.mp3',  type: 'audio/mpeg',      data: makeDummyMp3() },
  ]);
  const res = http.post(
    `${BASE_URL}/api/maps/${mapId}/memories`,
    body,
    { headers: { ...h, 'Content-Type': contentType }, tags: { name: 'POST_memory_upload' } }
  );

  check(res, { '업로드 201': r => r.status === 201 });
  sleep(randomInt(100, 200) / 10); // 10~20초 (S3 부하 조절)
}

// ── 지도 생성 + 삭제 ─────────────────────────────────────────
export function mapFunc({ tokens }) {
  const vuIdx = (__VU - 1) % MAP_VUS;
  const token = tokens[MAP_TOKEN_OFFSET + vuIdx];
  const h     = authHeaders(token);

  const res = http.post(
    `${BASE_URL}/api/map`,
    {
      request: http.file(JSON.stringify({
        mapName:     `부하테스트 VU${__VU} #${__ITER}`,
        description: '부하 테스트용',
        category:    'COUPLE',
      }), 'request', 'application/json'),
    },
    { headers: h, tags: { name: 'POST_map' } }
  );

  check(res, { '지도생성 201': r => r.status === 201 });
  sleep(randomInt(15, 30) / 10);
}

// ── 시나리오 종료 후 생성 데이터 일괄 정리 ──────────────────
export function teardown({ tokens, mapSnapshots }) {
  // 쓰기 맵 추억 전부 삭제
  for (let i = 0; i < WRITE_VUS; i++) {
    deleteAllMemories(WRITE_MAP_START + i, tokens[WRITE_TOKEN_OFFSET + i]);
  }
  // 업로드 맵 추억 전부 삭제
  for (let i = 0; i < UPLOAD_VUS; i++) {
    deleteAllMemories(UPLOAD_MAP_START + i, tokens[UPLOAD_TOKEN_OFFSET + i]);
  }
  // 지도생성 계정이 테스트 중 만든 맵만 삭제
  for (let i = 0; i < MAP_VUS; i++) {
    const token      = tokens[MAP_TOKEN_OFFSET + i];
    const originalIds = mapSnapshots[MAP_USER_START + i] || [];
    const res = http.get(`${BASE_URL}/api/map`, { headers: authHeaders(token) });
    if (res.status !== 200) continue;
    for (const m of JSON.parse(res.body).data) {
      if (!originalIds.includes(m.mapId)) {
        http.del(`${BASE_URL}/api/map/${m.mapId}`, null, { headers: authHeaders(token) });
      }
    }
  }
}

function deleteAllMemories(mapId, token) {
  const h = authHeaders(token);
  let page = 0;
  while (true) {
    const res = http.get(
      `${BASE_URL}/api/maps/${mapId}/memories?page=${page}&size=100`,
      { headers: h }
    );
    if (res.status !== 200) break;
    const body    = JSON.parse(res.body).data;
    const memories = body.content || [];
    if (memories.length === 0) break;
    for (const mem of memories) {
      http.del(`${BASE_URL}/api/maps/${mapId}/memories/${mem.memoryId}`, null, { headers: h });
    }
    if (body.last) break;
    page++;
  }
}

// ── 추억 텍스트 수정 ─────────────────────────────────────────
export function editFunc({ tokens }) {
  const idx   = (__VU - 1) % 100;
  const token = tokens[idx]; // test1..test100 (map 1..100 OWNER)
  const mapId = idx + 1;
  const h     = authHeaders(token);

  const memId = randomMemoryId(mapId);
  const res = http.put(
    `${BASE_URL}/api/maps/${mapId}/memories/${memId}`,
    {
      request: http.file(JSON.stringify({
        title:      `수정 VU${__VU} #${__ITER}`,
        content:    '부하 테스트 수정 내용',
        placeName:  '서울 강남구',
        memoryDate: '2025-06-15',
        category:   'DAILY',
      }), 'request', 'application/json'),
    },
    { headers: h, tags: { name: 'PUT_memory' } }
  );
  check(res, { '수정 200': r => r.status === 200 });
  sleep(randomInt(10, 30) / 10);
}
