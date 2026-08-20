// 사용자 여정 부하 — VU 고정, 실제 화면 흐름대로 호출. 규칙은 docs/load-test-plan.md
import http from 'k6/http';
import { check, sleep } from 'k6';
import { Trend } from 'k6/metrics';
import { SLO } from './lib/slo.js';
import { BASE_URL, RUN, makeHandleSummary } from './lib/run.js';
import { RANGES, userNumbers } from './lib/accounts.js';
import {
  fetchTokensBatch,
  authHeaders,
  jsonHeaders,
  createTextMemory,
  presignedUpload,
  UPLOAD_TAGS,
  randomMemoryId,
  randomInt,
  seedMemoryDate,
  seedMemoryCategory,
} from './helpers.js';

function envNum(name, def) {
  const v = __ENV[name];
  return v === undefined || v === '' ? def : Number(v);
}

// 업로드 구간 분해. 판정은 서버 구간(발급 + 완료)으로만 하고 나머지는 참고용이다.
const uploadServerMs = new Trend('upload_server_ms');
const uploadTransferMs = new Trend('upload_transfer_ms');
const uploadE2eMs = new Trend('upload_e2e_ms');

// 세션 소요 시간. iteration_duration은 시나리오 태그를 써서 phase 구분이 안 된다
const sessionMs = new Trend('session_ms');

// 워밍업과 측정을 한 시나리오로 돌리고 경과 시간으로 구분한다 (docs/load-test-plan.md 3절)
const WARMUP_MS = parseDuration(RUN.warmup);

// VU마다 자기 JS 런타임을 가지므로 모듈 전역이 VU별 상태가 된다
let startedAt = 0;

function parseDuration(str) {
  const re = /(\d+(?:\.\d+)?)(ms|s|m|h)/g;
  let total = 0;
  let m;
  while ((m = re.exec(String(str))) !== null) {
    const v = Number(m[1]);
    if (m[2] === 'ms') total += v;
    else if (m[2] === 's') total += v * 1000;
    else if (m[2] === 'm') total += v * 60000;
    else total += v * 3600000;
  }
  return total;
}

function currentPhase() {
  return Date.now() - startedAt > WARMUP_MS ? 'measure' : 'warmup';
}

// 요청 태그. 경계에 걸친 요청은 시작 시점 기준으로 분류된다.
function tag(name) {
  return { name: name, phase: currentPhase() };
}

const VUS = envNum('VUS', 1000);

// think time 배율. 1.0 = 실제 사람 속도, 0.3 = 3배 빠르게 넘김, 0 = 대기 없음
const THINK = envNum('THINK', 1.0);

// 파일 업로드 포함 여부. 끄면 파일 작성이 텍스트 작성으로 대체된다
const UPLOAD_ON = envNum('UPLOAD', 1) > 0;

// ── 여정 확률 (100세션 기준 횟수 / 100) ──────────────────────
const P = {
  invitations: envNum('P_INVITATIONS', 0.20),
  calendar: envNum('P_CALENDAR', 0.15),
  userMe: envNum('P_USER_ME', 0.10),
  friendList: envNum('P_FRIEND_LIST', 0.08),
  scrollPerMap: envNum('P_SCROLL', 0.53), // 지도 1회 열람당 목록 더보기 확률
  writeText: envNum('P_WRITE_TEXT', 0.08),
  writeUpload: envNum('P_WRITE_UPLOAD', 0.12),
  edit: envNum('P_EDIT', 0.02),
  mapCreate: envNum('P_MAP_CREATE', 0.10),
};

// 지도 열람 횟수 분포: 0회 15% / 1회 75% / 2회 10% → 기댓값 0.95
function mapOpenCount() {
  const r = Math.random();
  if (r < 0.15) return 0;
  if (r < 0.90) return 1;
  return 2;
}

// VU 시작 시점 분산(초). 전체가 같은 순간에 첫 API를 때리는 것을 막는다
const SPREAD = envNum('SPREAD', 10);

function shuffle(arr) {
  const a = arr.slice();
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    const t = a[i];
    a[i] = a[j];
    a[j] = t;
  }
  return a;
}

// ── API 이름 (Grafana, 결과 md의 분해 기준) ──────────────────
const READ_APIS = [
  'GET_map_list',
  'GET_map_detail',
  'GET_markers',
  'GET_memory_list',
  'GET_memory_detail',
  'GET_calendar',
  'GET_user_me',
  'GET_invitations',
  'GET_friend_list',
];
// presigned 전환 후 업로드는 서버 API 2개(발급, 완료)와 S3 직접 PUT 1개로 나뉜다.
// 서버 용량 판정에 들어가는 건 발급과 완료뿐이고 쓰기 SLO를 적용한다.
const WRITE_APIS = [
  'POST_memory_text',
  'PUT_memory',
  'POST_map',
  UPLOAD_TAGS.issue,
  UPLOAD_TAGS.complete,
];

// S3 직접 PUT — 서버를 거치지 않아 S3와 회선이 지배한다. 판정에서 제외하고 수치만 남긴다.
const REFERENCE_APIS = [UPLOAD_TAGS.put];

const ALL_APIS = READ_APIS.concat(WRITE_APIS, REFERENCE_APIS);

function buildScenarios() {
  // 워밍업과 측정을 한 시나리오로 돌린다. VU가 중간에 새로 생성되지 않는다.
  const totalMs = WARMUP_MS + parseDuration(RUN.duration);
  return {
    run: {
      executor: 'constant-vus',
      vus: VUS,
      duration: `${Math.round(totalMs / 1000)}s`,
      exec: 'journey',
      gracefulStop: '30s',
    },
  };
}

function buildThresholds() {
  const t = {};

  // API별 p95/p99. 개선 전까지 대부분 FAIL로 찍히는 게 정상이다
  for (const name of READ_APIS) {
    t[`http_req_duration{phase:measure,name:${name}}`] = [
      `p(95)<${SLO.READ_P95_MS}`,
      `p(99)<${SLO.READ_P99_MS}`,
    ];
  }
  for (const name of WRITE_APIS) {
    t[`http_req_duration{phase:measure,name:${name}}`] = [
      `p(95)<${SLO.WRITE_P95_MS}`,
      `p(99)<${SLO.WRITE_P99_MS}`,
    ];
  }
  // S3 직접 PUT은 지연 판정을 걸지 않는다. 수치는 통계용으로만 남긴다.
  for (const name of REFERENCE_APIS) {
    t[`http_req_duration{phase:measure,name:${name}}`] = ['p(95)>=0'];
  }

  // 오류율은 S3 PUT까지 전부 건다. 업로드가 실패하면 그건 지연이 아니라 고장이다.
  for (const name of ALL_APIS) {
    t[`http_req_failed{phase:measure,name:${name}}`] = [`rate<${SLO.ERROR_RATE}`];
  }

  // 오류가 계속 나면 시간 낭비하지 않고 중단한다. 지연이 아니라 정확성 기준이다.
  t['http_req_failed{phase:measure}'] = [
    { threshold: `rate<${SLO.ERROR_RATE}`, abortOnFail: true, delayAbortEval: '60s' },
  ];
  t['checks{phase:measure}'] = [`rate>${SLO.CHECK_RATE}`];

  // dropped_iterations는 안 건다. constant-vus는 항상 0이라 무의미하다

  // ── 통계 수집용 (판정 아님) ────────────────────────────────
  t['http_req_duration{phase:measure}'] = ['p(95)>=0'];
  t['http_req_waiting{phase:measure}'] = ['p(95)>=0'];
  t['http_reqs{phase:measure}'] = ['count>=0'];
  // 세션 소요 시간. iteration_duration은 phase 구분이 안 돼서 직접 기록한다
  t['session_ms{phase:measure}'] = ['p(95)>=0'];

  // 응답 수신량과 전송 시간. CloudFront 전환 라운드의 비교 기준이 된다
  t['data_received'] = ['count>=0'];
  t['http_req_receiving{phase:measure}'] = ['p(95)>=0'];

  for (const name of ALL_APIS) {
    t[`http_reqs{phase:measure,name:${name}}`] = ['count>=0'];
    t[`http_req_waiting{phase:measure,name:${name}}`] = ['p(95)>=0'];
    t[`http_req_receiving{phase:measure,name:${name}}`] = ['p(95)>=0'];
  }

  return t;
}

export const options = {
  scenarios: buildScenarios(),
  thresholds: buildThresholds(),
  teardownTimeout: '20m',
  summaryTrendStats: ['avg', 'min', 'med', 'p(90)', 'p(95)', 'p(99)', 'max'],
};

export const handleSummary = makeHandleSummary(ALL_APIS);

// ── think time ───────────────────────────────────────────────
function think(min, max) {
  if (THINK <= 0) return;
  sleep((min + Math.random() * (max - min)) * THINK);
}

// ── setup ────────────────────────────────────────────────────

export function setup() {
  // 세션당 호출 수 기댓값 (여정 정의와 일치해야 한다)
  const mapOpens = 0.95;
  const callsPerSession =
    1 + // 홈
    P.invitations +
    mapOpens * (3 + 2 + P.scrollPerMap) + // 지도정보 + 마커 + 목록, 추억상세 2, 스크롤
    P.calendar +
    P.userMe +
    P.friendList +
    P.writeText +
    P.writeUpload +
    P.edit +
    P.mapCreate;

  console.log('');
  console.log('  ── 사용자 여정 부하 (VU 고정) ──────────────────');
  console.log(`  VU         : ${VUS}명 고정`);
  console.log(`  think 배율 : ${THINK} ${THINK >= 1 ? '(실제 사람 속도)' : '(가속 — 문서에 명시할 것)'}`);
  console.log(`  세션당 호출: 약 ${callsPerSession.toFixed(1)}회`);
  console.log(`  구간       : 워밍업 ${RUN.warmup} → 측정 ${RUN.duration}`);
  console.log(
    `  SLO p95    : 조회 ${SLO.READ_P95_MS}ms / 쓰기 ${SLO.WRITE_P95_MS}ms / 업로드 ${SLO.UPLOAD_P95_MS}ms`
  );
  console.log(`  환경       : ${RUN.machine} | ${RUN.appMode} | ${RUN.dbMode}`);
  console.log('');
  console.log('  처리율은 입력이 아니라 결과다. 목표에 못 미치면');
  console.log('  VUS를 올리거나 THINK를 낮춰서 포화시킨다.');
  console.log('');

  const tokens = {
    read: fetchTokensBatch(userNumbers(RANGES.read)),
    write: fetchTokensBatch(userNumbers(RANGES.write)),
    upload: fetchTokensBatch(userNumbers(RANGES.upload)),
    mapc: fetchTokensBatch(userNumbers(RANGES.mapCreate)),
  };

  console.log(`  토큰 ${tokens.read.length + tokens.write.length + tokens.upload.length + tokens.mapc.length}개 발급 완료. 지금부터 워밍업 ${RUN.warmup}.`);
  console.log('');

  // 워밍업과 측정의 경계를 재는 기준 시각. 토큰 발급이 끝난 뒤부터 센다.
  // 발급 전에 재면 로그인 배치 시간이 워밍업 구간을 다 잡아먹는다.
  return { startedAt: Date.now(), tokens: tokens };
}

// 계정 배정 — VU 하나가 사용자 한 명. 쓰기와 지도 생성만 다른 계정 (lib/accounts.js)

function pick(tokens, mapStart) {
  const i = (__VU - 1) % tokens.length;
  return { token: tokens[i], h: authHeaders(tokens[i]), mapId: mapStart + i, idx: i };
}

function reader(data) {
  return pick(data.tokens.read, RANGES.read.mapStart);
}

function writer(data) {
  return pick(data.tokens.write, RANGES.write.mapStart);
}

function uploader(data) {
  return pick(data.tokens.upload, RANGES.upload.mapStart);
}

function mapCreator(data) {
  return pick(data.tokens.mapc, 0);
}

// ── 여정 ─────────────────────────────────────────────────────
// 1 iteration = 앱을 한 번 열어서 닫을 때까지

function viewInvitations(me) {
  const res = http.get(`${BASE_URL}/api/map/invitations`, {
    headers: me.h,
    tags: tag('GET_invitations'),
  });
  check(res, { '초대목록 200': (r) => r.status === 200 }, { phase: currentPhase() });
  think(5, 10);
}

function viewCalendar(me) {
  const res = http.get(`${BASE_URL}/api/calendar/memories?year=2024`, {
    headers: me.h,
    tags: tag('GET_calendar'),
  });
  check(res, { '캘린더 200': (r) => r.status === 200 }, { phase: currentPhase() });
  think(5, 10);
}

function viewMyPage(me) {
  const res = http.get(`${BASE_URL}/api/users/me`, {
    headers: me.h,
    tags: tag('GET_user_me'),
  });
  check(res, { '내정보 200': (r) => r.status === 200 }, { phase: currentPhase() });
  think(5, 10);
}

function viewFriends(me) {
  const res = http.get(`${BASE_URL}/api/friend/list`, {
    headers: me.h,
    tags: tag('GET_friend_list'),
  });
  check(res, { '친구목록 200': (r) => r.status === 200 }, { phase: currentPhase() });
  think(5, 10);
}

export function journey(data) {
  startedAt = data.startedAt;
  const iterStart = Date.now();

  // 첫 반복만 무작위로 늦게 시작한다. VU 전체가 같은 순간에 같은 API를
  // 때리는 것을 막는다. 두 번째 반복부터는 think time이 알아서 흩어놓는다.
  if (__ITER === 0 && SPREAD > 0) {
    sleep(Math.random() * SPREAD);
  }

  const me = reader(data);

  // 앱 진입 — 홈 화면은 지도 목록이다. 여기만 순서가 고정이다.
  openHome(me);
  think(5, 10);

  // 나머지 화면은 순서를 매번 섞는다. 확률은 그대로라 API 비율은 유지된다
  const steps = [];

  if (Math.random() < P.invitations) steps.push(() => viewInvitations(me));
  if (Math.random() < P.calendar) steps.push(() => viewCalendar(me));
  if (Math.random() < P.userMe) steps.push(() => viewMyPage(me));
  if (Math.random() < P.friendList) steps.push(() => viewFriends(me));

  const opens = mapOpenCount();
  for (let n = 0; n < opens; n++) steps.push(() => openMap(me));

  const w = Math.random();
  if (w < P.writeText) {
    steps.push(() => writeText(data));
  } else if (w < P.writeText + P.writeUpload) {
    // 업로드 제외 시 텍스트로 대체해 쓰기 총량을 유지한다
    steps.push(() => (UPLOAD_ON ? writeWithFiles(data) : writeText(data)));
  }

  if (Math.random() < P.edit) steps.push(() => editMemory(data, me));
  if (Math.random() < P.mapCreate) steps.push(() => createMap(data));

  for (const step of shuffle(steps)) {
    step();
  }

  // 세션 소요 시간. think time이 포함돼 있으므로 절대값보다 전후 변화를 본다.
  sessionMs.add(Date.now() - iterStart, { phase: currentPhase() });
}

// ── 화면 단위 동작 ───────────────────────────────────────────

function openHome(me) {
  const res = http.get(`${BASE_URL}/api/map`, {
    headers: me.h,
    tags: tag('GET_map_list'),
  });
  check(res, { '지도목록 200': (r) => r.status === 200 }, { phase: currentPhase() });
}

// 지도 상세 화면 하나가 API 3개를 부른다. 이게 비율의 출처다.
function openMap(me) {
  const detail = http.get(`${BASE_URL}/api/map/${me.mapId}`, {
    headers: me.h,
    tags: tag('GET_map_detail'),
  });
  check(detail, { '지도상세 200': (r) => r.status === 200 }, { phase: currentPhase() });

  const markers = http.get(`${BASE_URL}/api/maps/${me.mapId}/memories/markers`, {
    headers: me.h,
    tags: tag('GET_markers'),
  });
  check(markers, { '마커 200': (r) => r.status === 200 }, { phase: currentPhase() });

  const list = http.get(`${BASE_URL}/api/maps/${me.mapId}/memories?page=0&size=10`, {
    headers: me.h,
    tags: tag('GET_memory_list'),
  });
  check(list, { '추억목록 200': (r) => r.status === 200 }, { phase: currentPhase() });

  think(5, 10); // 지도 보면서 마커를 훑는 시간

  // 추억 상세 1~3개 (기댓값 2)
  const reads = randomInt(1, 3);
  for (let i = 0; i < reads; i++) {
    const res = http.get(
      `${BASE_URL}/api/maps/${me.mapId}/memories/${randomMemoryId(me.mapId)}`,
      { headers: me.h, tags: tag('GET_memory_detail') }
    );
    check(res, { '추억상세 200': (r) => r.status === 200 }, { phase: currentPhase() });
    think(5, 10);
  }

  // 목록 더보기
  if (Math.random() < P.scrollPerMap) {
    const res = http.get(
      `${BASE_URL}/api/maps/${me.mapId}/memories?page=${randomInt(1, 4)}&size=10`,
      { headers: me.h, tags: tag('GET_memory_list') }
    );
    check(res, { '추억목록 200': (r) => r.status === 200 }, { phase: currentPhase() });
    think(5, 10);
  }
}

function memoryBody(title, content, place, address, date, lat, lng, category) {
  return {
    title: title,
    content: content,
    placeName: place,
    address: address,
    memoryDate: date,
    latitude: lat,
    longitude: lng,
    category: category,
  };
}

function writeText(data) {
  const c = writer(data);
  think(15, 30); // 작성 폼을 채우는 시간
  const res = createTextMemory(
    c.mapId,
    c.token,
    memoryBody(
      `여정 쓰기 ${__VU}-${__ITER}`,
      '텍스트만 있는 추억',
      '서울 강남구',
      '서울시 강남구 테헤란로 123',
      '2025-06-15',
      37.5665,
      126.978,
      'DAILY'
    ),
    { phase: currentPhase() }
  );
  check(res, { '쓰기 201': (r) => r.status === 201 }, { phase: currentPhase() });
}

// presigned 3단계. 판정은 발급과 완료만, S3 PUT은 참고 지표
function writeWithFiles(data) {
  const c = uploader(data);
  think(20, 40); // 사진 고르는 시간

  const r = presignedUpload(
    c.mapId,
    c.token,
    memoryBody(
      `여정 업로드 ${__VU}-${__ITER}`,
      'JPEG x3 + MP3 x1',
      '부산 해운대',
      '부산시 해운대구 해운대해변로 264',
      '2025-06-20',
      35.1587,
      129.1604,
      'TRAVEL'
    ),
    { phase: currentPhase() }
  );

  check(r, { '업로드 3단계 성공': (x) => x.ok }, { phase: currentPhase() });
  if (!r.ok) return;

  // 서버 구간과 전송 구간을 나눠 기록한다. 판정은 서버 구간(발급 + 완료)으로만 한다.
  uploadServerMs.add(r.serverMs);
  uploadTransferMs.add(r.transferMs);
  uploadE2eMs.add(r.e2eMs);
}

// 추억 수정 — memoryDate와 category를 시드값으로 보내 분포를 보존한다 (멱등)
function editMemory(data, me) {
  const memId = randomMemoryId(me.mapId);
  think(15, 30);
  const res = http.put(
    `${BASE_URL}/api/maps/${me.mapId}/memories/${memId}`,
    JSON.stringify({
      title: `여정 수정 ${__VU}-${__ITER}`,
      content: '부하 테스트 수정 내용',
      placeName: '서울 강남구',
      memoryDate: seedMemoryDate(memId),
      category: seedMemoryCategory(memId),
    }),
    { headers: jsonHeaders(me.token), tags: tag('PUT_memory') }
  );
  check(res, { '수정 200': (r) => r.status === 200 }, { phase: currentPhase() });
}

function createMap(data) {
  const c = mapCreator(data);
  think(15, 30);
  const uniq = String(Date.now()).slice(-7);
  const res = http.post(
    `${BASE_URL}/api/map`,
    JSON.stringify({
      mapName: `J${__VU}-${__ITER}-${uniq}`.slice(0, 20),
      description: '부하테스트',
      category: 'COUPLE',
    }),
    { headers: jsonHeaders(c.token), tags: tag('POST_map') }
  );
  check(res, { '지도생성 201': (r) => r.status === 201 }, { phase: currentPhase() });
}

// teardown — 정리는 backend/scripts/load-test-cleanup.sql이 한다

export function teardown() {
  if ((__ENV.CLEANUP || 'false') === 'false') {
    console.log('');
    console.log('  생성 데이터를 정리하지 않았다.');
    console.log('  라운드가 바뀌면 backend/scripts/load-test-cleanup.sql을 실행할 것.');
    console.log('');
  }
}
