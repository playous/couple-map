import http from 'k6/http';

export const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';

// ── 시드 데이터 기준 상수 ──────────────────────────────────────
// map_id 1..50  : COUPLE, 추억 200개씩 (read 전용)
// map_id 101..  : 쓰기 테스트용 (빈 지도)
// user_id = i   ↔  providerId = test{i}  ↔  map_id = i (Round1 OWNER)
export const READ_MAP_IDS = Array.from({ length: 500 }, (_, i) => i + 1); // [1..500]

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
    const responses = http.batch(
      chunk.map(n => ({ method: 'POST', url: `${BASE_URL}/api/dev/login/test${n}` }))
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
// 시드 기준: mapId N (1..50) → memory_id 범위 [(N-1)*200+1 .. N*200]
export function randomMemoryId(mapId) {
  if (mapId <= 100) {
    const base = (mapId - 1) * 200;
    return base + randomInt(1, 200);
  } else {
    const base = 100 * 200 + (mapId - 101) * 50;
    return base + randomInt(1, 50);
  }
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

// ── multipart request 헬퍼 ────────────────────────────────────
export function memoryRequestBlob(fields) {
  return http.file(JSON.stringify(fields), 'request', 'application/json');
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
