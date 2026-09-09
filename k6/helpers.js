import http from 'k6/http';

export const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';

// ── 시드 데이터 기준 상수 (load-test-seed.sql v3과 연동) ──────
// map_id 1..200     : 헤비 지도, 추억 500개씩 (read 전용)
// map_id 201..4000  : 라이트 지도, 추억 50개씩 (read 전용)
// map_id 4001..     : 쓰기, 업로드 테스트용 (빈 지도)
// user_id = i  =  providerId test{i}  =  map_id i (OWNER)
export const HEAVY_MAP_COUNT = 200;
export const HEAVY_MEMS_PER_MAP = 500;
export const LIGHT_MAP_START = 201;
export const LIGHT_MEMS_PER_MAP = 50;
export const READ_MAP_IDS = Array.from({ length: 4000 }, (_, i) => i + 1); // [1..4000]

// ── 인증 ──────────────────────────────────────────────────────
export function fetchToken(userNum) {
  const res = http.post(
    `${BASE_URL}/api/dev/login/test${userNum}`,
    null,
    { tags: { name: 'setup_login' } }
  );
  if (res.status !== 200) {
    throw new Error(`Login failed for test${userNum}: ${res.status} ${res.body}`);
  }
  return JSON.parse(res.body).data.accessToken;
}

// 50개씩 병렬 배치 발급 (순차 발급 대비 ~50배 빠름)
export function fetchTokensBatch(userNums) {
  const CHUNK = 50;
  const tokens = [];
  for (let i = 0; i < userNums.length; i += CHUNK) {
    const chunk = userNums.slice(i, i + CHUNK);
    // name 태그가 없으면 URL이 그대로 라벨이 되어 계정 수만큼 시계열이 생긴다
    const responses = http.batch(
      chunk.map(n => ({
        method: 'POST',
        url: `${BASE_URL}/api/dev/login/test${n}`,
        params: { tags: { name: 'setup_login' } },
      }))
    );
    for (const res of responses) {
      if (res.status !== 200) {
        throw new Error(`Login failed: ${res.status} ${res.body}`);
      }
      tokens.push(JSON.parse(res.body).data.accessToken);
    }
  }
  return tokens;
}

export function authHeaders(token) {
  return { Authorization: `Bearer ${token}` };
}

// ── ID 헬퍼 ───────────────────────────────────────────────────
// 시드 v3 기준:
//   mapId N (1..200)    → memory_id [(N-1)*500+1 .. N*500]
//   mapId N (201..4000) → memory_id [100000+(N-201)*50+1 .. +50]
export function randomMemoryId(mapId) {
  if (mapId <= HEAVY_MAP_COUNT) {
    const base = (mapId - 1) * HEAVY_MEMS_PER_MAP;
    return base + randomInt(1, HEAVY_MEMS_PER_MAP);
  } else {
    const base =
      HEAVY_MAP_COUNT * HEAVY_MEMS_PER_MAP + (mapId - LIGHT_MAP_START) * LIGHT_MEMS_PER_MAP;
    return base + randomInt(1, LIGHT_MEMS_PER_MAP);
  }
}

// ── 시드 분포 보존 헬퍼 ───────────────────────────────────────
// load-test-seed.sql 기준:
//   memory_date = '2023-01-01' + ((mem_seq - 1) % 1095)일  → 2023~2025년에 균등
//   category    = ELT((mem_seq % 5) + 1, DATE, TRAVEL, FOOD, ANNIVERSARY, DAILY)
// mem_seq는 AUTO_INCREMENT와 함께 1부터 증가하므로 memory_id로 원래 값을
// 되돌릴 수 있다 (randomMemoryId와 같은 가정).
//
// 수정 부하(editFunc)가 이 분포를 바꾸면 안 되는 이유:
// 캘린더 API가 year=2024로 조회하는데, 수정이 memoryDate를 고정값으로
// 덮어쓰면 라운드를 돌수록 2024년 추억 수가 줄어 아무것도 안 고쳐도
// 캘린더가 저절로 빨라진다. 개선 효과와 구분이 불가능해진다.
export function seedMemoryDate(memoryId) {
  const days = (memoryId - 1) % 1095;
  const d = new Date(Date.UTC(2023, 0, 1));
  d.setUTCDate(d.getUTCDate() + days);
  return d.toISOString().slice(0, 10);
}

export function seedMemoryCategory(memoryId) {
  return ['DATE', 'TRAVEL', 'FOOD', 'ANNIVERSARY', 'DAILY'][memoryId % 5];
}

export function randomItem(arr) {
  return arr[Math.floor(Math.random() * arr.length)];
}

export function randomInt(min, max) {
  return Math.floor(Math.random() * (max - min + 1)) + min;
}

// ── 1MB 더미 JPEG 생성 ────────────────────────────────────────
export function makeDummyJpeg() {
  const size = 1024 * 1024;
  const buf = new Uint8Array(size);
  buf[0] = 0xFF; buf[1] = 0xD8; // SOI
  buf[2] = 0xFF; buf[3] = 0xE0; // APP0
  buf[size - 2] = 0xFF; buf[size - 1] = 0xD9; // EOI
  return buf.buffer;
}

// ── 3MB 더미 MP3 생성 ────────────────────────────────────────
export function makeDummyMp3() {
  const size = 3 * 1024 * 1024;
  const buf = new Uint8Array(size);
  buf[0] = 0xFF; buf[1] = 0xFB; // MP3 sync word
  return buf.buffer;
}

// ── multipart request 헬퍼 (수정 API 전용 — 생성은 JSON으로 바뀜) ──
export function memoryRequestBlob(fields) {
  return http.file(JSON.stringify(fields), 'request', 'application/json');
}

export function jsonHeaders(token) {
  return { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' };
}

// extraTags로 phase를 받는다. 없으면 측정 구간 집계에서 빠진다
export function createTextMemory(mapId, token, fields, extraTags) {
  return http.post(`${BASE_URL}/api/maps/${mapId}/memories`, JSON.stringify(fields), {
    headers: jsonHeaders(token),
    tags: Object.assign({ name: 'POST_memory_text' }, extraTags || {}),
  });
}

// ── presigned 업로드 3단계 ────────────────────────────────────
export const UPLOAD_FILE_SPECS = [
  { filename: 'photo1.jpg', contentType: 'image/jpeg', size: 1024 * 1024 },
  { filename: 'photo2.jpg', contentType: 'image/jpeg', size: 1024 * 1024 },
  { filename: 'photo3.jpg', contentType: 'image/jpeg', size: 1024 * 1024 },
  { filename: 'audio.mp3', contentType: 'audio/mpeg', size: 3 * 1024 * 1024 },
];

export const UPLOAD_TAGS = {
  issue: 'POST_upload_urls',
  put: 'PUT_s3_direct',
  complete: 'POST_memory_complete',
};

function uploadFileBody(spec) {
  return spec.contentType === 'audio/mpeg' ? makeDummyMp3() : makeDummyJpeg();
}

// S3 직접 PUT을 건너뛴다. 기본 켜짐.
//
// 서버는 발급과 완료만 처리하고 PUT은 서버를 거치지 않으므로, 판정에
// 기여하는 바가 없다. 반면 실제로 올리면 세션의 12%가 6MB씩 쏴서
// 생성기 업링크가 먼저 포화된다. 2,000 VU 실행에서 PUT p95 49초,
// 오류율 36%가 나왔고 VU가 거기 묶여 조회 측정까지 왜곡됐다.
// 완료 API도 0건 측정됐다 — PUT이 실패하면 완료를 안 보내기 때문이다.
//
// completeUpload는 S3에 파일이 있는지 검사하지 않으므로(HeadObject 미사용)
// 건너뛰어도 발급과 완료는 정상 측정된다.
// E2E 체감을 재려면 SKIP_S3=0으로 소수 VU에서만 돌린다.
const SKIP_S3 = (__ENV.SKIP_S3 || '1') !== '0';

// 발급 -> S3 직접 PUT -> 완료. 실패해도 단계별 응답을 돌려줘 호출부가 check 할 수 있게 한다
export function presignedUpload(mapId, token, memoryFields, extraTags) {
  const et = extraTags || {};
  const h = jsonHeaders(token);
  const startedAt = Date.now();

  const issueRes = http.post(
    `${BASE_URL}/api/maps/${mapId}/memories/uploads`,
    JSON.stringify({ files: UPLOAD_FILE_SPECS }),
    { headers: h, tags: Object.assign({ name: UPLOAD_TAGS.issue }, et) }
  );
  if (issueRes.status !== 200) {
    return { ok: false, step: 'issue', issueRes: issueRes };
  }

  let issued;
  try {
    issued = JSON.parse(issueRes.body).data;
  } catch (e) {
    return { ok: false, step: 'issue', issueRes: issueRes };
  }

  let transferMs = 0;
  if (!SKIP_S3) {
    for (let i = 0; i < UPLOAD_FILE_SPECS.length; i++) {
      const spec = UPLOAD_FILE_SPECS[i];
      const putRes = http.put(issued.items[i].url, uploadFileBody(spec), {
        headers: { 'Content-Type': spec.contentType },
        tags: Object.assign({ name: UPLOAD_TAGS.put }, et),
      });
      transferMs += putRes.timings.duration;
      if (putRes.status !== 200) {
        return { ok: false, step: 'put', issueRes: issueRes, putRes: putRes, transferMs: transferMs };
      }
    }
  }

  const completeRes = http.post(
    `${BASE_URL}/api/maps/${mapId}/memories/complete`,
    JSON.stringify({
      uploadId: issued.uploadId,
      request: memoryFields,
      files: issued.items.map((item, idx) => ({ fileKey: item.fileKey, displayOrder: idx + 1 })),
    }),
    { headers: h, tags: Object.assign({ name: UPLOAD_TAGS.complete }, et) }
  );

  return {
    ok: completeRes.status === 201,
    step: 'complete',
    issueRes: issueRes,
    completeRes: completeRes,
    transferMs: transferMs,
    e2eMs: Date.now() - startedAt,
    serverMs: issueRes.timings.duration + completeRes.timings.duration,
  };
}

// ── 멀티파일 multipart 수동 조립 ─────────────────────────────
// k6는 동일 필드명 배열 전송을 지원하지 않으므로 ArrayBuffer로 직접 조립
// parts: [{ name, filename, type, data: ArrayBuffer|string }, ...]
function strToBytes(str) {
  const bytes = [];
  for (let i = 0; i < str.length; i++) {
    const code = str.charCodeAt(i);
    if (code < 0x80) {
      bytes.push(code);
    } else if (code < 0x800) {
      bytes.push(0xC0 | (code >> 6), 0x80 | (code & 0x3F));
    } else if (code < 0xD800 || code >= 0xE000) {
      bytes.push(0xE0 | (code >> 12), 0x80 | ((code >> 6) & 0x3F), 0x80 | (code & 0x3F));
    } else {
      const cp = 0x10000 + ((code - 0xD800) << 10) + (str.charCodeAt(++i) - 0xDC00);
      bytes.push(0xF0 | (cp >> 18), 0x80 | ((cp >> 12) & 0x3F), 0x80 | ((cp >> 6) & 0x3F), 0x80 | (cp & 0x3F));
    }
  }
  return new Uint8Array(bytes);
}

export function buildMultipart(parts) {
  const boundary = 'k6Boundary' + Math.random().toString(36).slice(2, 10);
  const CRLF = '\r\n';

  const chunks = [];
  for (const part of parts) {
    let header = `--${boundary}${CRLF}`;
    header += `Content-Disposition: form-data; name="${part.name}"`;
    if (part.filename) header += `; filename="${part.filename}"`;
    header += CRLF;
    if (part.type) header += `Content-Type: ${part.type}${CRLF}`;
    header += CRLF;

    chunks.push(strToBytes(header));
    chunks.push(part.data instanceof ArrayBuffer ? new Uint8Array(part.data) : strToBytes(part.data));
    chunks.push(strToBytes(CRLF));
  }
  chunks.push(strToBytes(`--${boundary}--${CRLF}`));

  let totalLen = 0;
  for (const c of chunks) totalLen += c.byteLength;

  const body = new Uint8Array(totalLen);
  let offset = 0;
  for (const c of chunks) { body.set(c, offset); offset += c.byteLength; }

  return { body: body.buffer, contentType: `multipart/form-data; boundary=${boundary}` };
}
