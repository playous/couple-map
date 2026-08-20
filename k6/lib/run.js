/**
 * 실행 메타데이터 수집과 결과 기록.
 *
 * 부하 테스트 결과는 "어떤 환경에서 쟀는지"가 빠지면 비교가 불가능하다.
 * 머신이 바뀌면 수치가 바뀌고, DB 위치가 바뀌면 병목이 바뀐다.
 * 그래서 모든 실행은 환경 정보를 함께 기록한다.
 */

function env(name, def) {
  const v = __ENV[name];
  return v === undefined || v === '' ? def : v;
}

export const BASE_URL = env('BASE_URL', 'http://localhost:8080');

function defaultRunId() {
  const stamp = new Date().toISOString().slice(0, 16).replace(/[-:T]/g, '');
  return `${env('API', 'run')}-r${env('RATE', '0')}-${stamp}`;
}

export const RUN = {
  id: env('RUN_ID', defaultRunId()),

  // 측정 대상과 부하량
  api: env('API', 'list'),
  rate: Number(env('RATE', '20')),
  warmup: env('WARMUP', '30s'),
  duration: env('DURATION', '3m'),

  // ── 환경 기록 (비워두면 비교가 불가능해진다) ──
  machine: env('MACHINE', 'unknown'), // 예: "Ultra9-185H 16C22T 64GB"
  appMode: env('APP_MODE', 'unknown'), // 예: "docker --cpus=4 --memory=2g -Xmx1g"
  dbMode: env('DB_MODE', 'unknown'), // 예: "local-docker-mysql8" | "rds-t3.micro"
  commit: env('COMMIT', 'unknown'), // git rev-parse --short HEAD
  note: env('NOTE', ''), // 예: "baseline" | "S3 업로드 트랜잭션 분리 후"

  // ── DB 환경 (래퍼가 lib/db-env.ps1로 조회해 주입) ──
  // 시드 v2의 전제는 "데이터가 InnoDB 버퍼풀보다 크다"는 것이다.
  // 버퍼풀은 로컬 MySQL 설정이라 git 밖에 있으므로 매 실행마다 기록한다.
  // 배율이 1.0 미만이면 전부 메모리에 올라가 인덱스 개선이 측정되지 않는다.
  // 2026-08-12 실측: 128MB / 199MB / 1.56배
  dbPoolMb: env('DB_POOL_MB', 'unknown'),
  dbSizeMb: env('DB_SIZE_MB', 'unknown'),
  dbRatio: env('DB_RATIO', 'unknown'),
};

// ── 요약 렌더링 ──────────────────────────────────────────────

function metric(data, name) {
  return data && data.metrics ? data.metrics[name] : null;
}

function value(data, name, key) {
  const m = metric(data, name);
  if (!m || !m.values) return null;
  const v = m.values[key];
  return v === undefined ? null : v;
}

function fmt(v, digits) {
  if (v === null || v === undefined || Number.isNaN(v)) return 'n/a';
  return Number(v).toFixed(digits === undefined ? 2 : digits);
}

function pad(s, width) {
  let out = String(s);
  while (out.length < width) out += ' ';
  return out;
}

/**
 * k6는 threshold에 등장한 태그 셀렉터만 서브메트릭으로 만들어 요약에 남긴다.
 * 그래서 각 스크립트는 "항상 통과하는" 통계 수집용 threshold를 함께 선언한다.
 * (예: p(95)>=0, count>=0) 이런 항목은 판정이 아니므로 판정 표에서 걸러낸다.
 */
const STATS_ONLY_EXPR = />=\s*0$/;

function thresholdRows(data) {
  const rows = [];
  const metrics = (data && data.metrics) || {};
  for (const name of Object.keys(metrics)) {
    const th = metrics[name].thresholds;
    if (!th) continue;
    for (const expr of Object.keys(th)) {
      if (STATS_ONLY_EXPR.test(expr)) continue; // 통계 수집용 — 판정 아님
      const entry = th[expr];
      // k6 버전에 따라 { ok: true } 또는 { fails: 0 } 형태로 온다
      let ok;
      if (entry && entry.ok !== undefined) ok = entry.ok;
      else if (entry && entry.fails !== undefined) ok = entry.fails === 0;
      else ok = true;
      rows.push({ metric: name, expr, ok });
    }
  }
  return rows;
}

/**
 * 측정 구간 요청이 0건이면 무조건 INVALID다.
 *
 * threshold는 데이터가 없으면 공허하게 참이 되므로, setup 실패나 조기 중단으로
 * 한 건도 못 보낸 실행이 PASS로 기록된다. 그런 결과 파일이 남으면 나중에
 * "이때는 통과했었네"로 오독한다. 판정보다 먼저 걸러낸다.
 */
function verdict(rows, dropped, reqs) {
  if (reqs === null || reqs === 0) return 'INVALID';
  if (dropped !== null && dropped > 0) return 'INVALID';
  return rows.every((r) => r.ok) ? 'PASS' : 'FAIL';
}

/** '30s' | '3m' | '1m30s' 같은 k6 duration 문자열 → 초 */
function durationSec(str) {
  const re = /(\d+(?:\.\d+)?)(ms|s|m|h)/g;
  let total = 0;
  let m;
  while ((m = re.exec(String(str))) !== null) {
    const v = Number(m[1]);
    if (m[2] === 'ms') total += v / 1000;
    else if (m[2] === 's') total += v;
    else if (m[2] === 'm') total += v * 60;
    else total += v * 3600;
  }
  return total;
}

function collect(data) {
  const measure = '{phase:measure}';
  // 실제 RPS는 측정 구간의 요청 수 / 측정 구간 길이로 계산한다.
  // 태그 없는 http_reqs.rate는 setup 로그인 배치와 teardown 삭제 요청까지
  // 포함하고 분모가 전체 실행 시간이라 목표 도착률과 비교할 수 없다.
  const measureReqs = value(data, `http_reqs${measure}`, 'count');
  const measureSec = durationSec(RUN.duration);
  return {
    reqs: measureReqs,
    rps: measureReqs === null || measureSec <= 0 ? null : measureReqs / measureSec,
    iters: value(data, 'iterations', 'count'),
    dropped: value(data, 'dropped_iterations', 'count'),
    avg: value(data, `http_req_duration${measure}`, 'avg'),
    med: value(data, `http_req_duration${measure}`, 'med'),
    p90: value(data, `http_req_duration${measure}`, 'p(90)'),
    p95: value(data, `http_req_duration${measure}`, 'p(95)'),
    p99: value(data, `http_req_duration${measure}`, 'p(99)'),
    max: value(data, `http_req_duration${measure}`, 'max'),
    failRate: value(data, `http_req_failed${measure}`, 'rate'),
    checkRate: value(data, `checks${measure}`, 'rate'),
    waiting: value(data, `http_req_waiting${measure}`, 'p(95)'),
  };
}

/**
 * API별 분해. 혼합 시나리오에서 여러 엔드포인트가 동시에 도는 경우,
 * 전체 합산 p95는 느린 API를 빠른 API가 희석해 버려 의미가 없다.
 * name 태그별로 따로 뽑아야 어느 API가 먼저 무너졌는지 보인다.
 */
function collectPerApi(data, names) {
  if (!names || names.length === 0) return [];
  return names.map(function (name) {
    const sel = `{phase:measure,name:${name}}`;
    return {
      name: name,
      reqs: value(data, `http_reqs${sel}`, 'count'),
      p95: value(data, `http_req_duration${sel}`, 'p(95)'),
      p99: value(data, `http_req_duration${sel}`, 'p(99)'),
      avg: value(data, `http_req_duration${sel}`, 'avg'),
      // waiting = 서버 처리 시간(TTFB). duration과 벌어지면 전송 시간이 크다는 뜻
      // (업로드처럼 요청 바디가 큰 API를 구분하는 데 쓴다)
      waiting: value(data, `http_req_waiting${sel}`, 'p(95)'),
      failRate: value(data, `http_req_failed${sel}`, 'rate'),
    };
  });
}

function renderText(data, apiNames) {
  const s = collect(data);
  const rows = thresholdRows(data);
  const v = verdict(rows, s.dropped, s.reqs);

  const lines = [];
  lines.push('');
  lines.push('════════════════════════════════════════════════════════');
  lines.push(`  ${RUN.id}`);
  lines.push(`  API=${RUN.api}  RATE=${RUN.rate}/s  DURATION=${RUN.duration}`);
  lines.push('════════════════════════════════════════════════════════');
  lines.push(`  판정          : ${v}`);
  lines.push('  ── 측정 구간 (워밍업 제외) ──');
  lines.push(`  요청 수       : ${s.reqs === null ? 'n/a' : s.reqs}`);
  lines.push(`  실제 RPS      : ${fmt(s.rps)}`);
  lines.push(`  p95           : ${fmt(s.p95)} ms`);
  lines.push(`  p99           : ${fmt(s.p99)} ms`);
  lines.push(`  평균 / 중앙값 : ${fmt(s.avg)} / ${fmt(s.med)} ms`);
  lines.push(`  최대          : ${fmt(s.max)} ms`);
  lines.push(`  오류율        : ${fmt(s.failRate === null ? null : s.failRate * 100)} %`);
  lines.push(`  dropped_iter  : ${s.dropped === null ? 'n/a' : s.dropped}`);

  const per = collectPerApi(data, apiNames);
  if (per.length > 0) {
    lines.push('  ── API별 (혼합 시나리오) ──');
    lines.push(
      '  ' + pad('API', 22) + pad('요청', 9) + pad('p95', 11) + pad('p99', 11) +
        pad('서버p95', 11) + '오류율'
    );
    for (const p of per) {
      if (p.reqs === null) continue;
      lines.push(
        '  ' +
          pad(p.name, 22) +
          pad(String(p.reqs), 9) +
          pad(fmt(p.p95, 1) + 'ms', 11) +
          pad(fmt(p.p99, 1) + 'ms', 11) +
          pad(fmt(p.waiting, 1) + 'ms', 11) +
          fmt(p.failRate === null ? null : p.failRate * 100, 2) + '%'
      );
    }
  }

  lines.push('  ── 기준 판정 ──');
  for (const r of rows) {
    lines.push(`  ${r.ok ? 'OK  ' : 'FAIL'}  ${r.metric} → ${r.expr}`);
  }
  if (s.dropped !== null && s.dropped > 0) {
    lines.push('');
    lines.push('  ⚠ dropped_iterations > 0');
    lines.push('    부하 생성기가 목표 도착률을 못 냈다는 뜻이다.');
    lines.push('    maxVUs 부족이거나 k6 자체가 포화된 것이므로');
    lines.push('    이 실행은 서버 한계로 기록하지 않는다.');
  }
  lines.push('════════════════════════════════════════════════════════');
  lines.push('');
  return lines.join('\n');
}

function renderMarkdown(data, apiNames) {
  const s = collect(data);
  const rows = thresholdRows(data);
  const v = verdict(rows, s.dropped, s.reqs);

  const L = [];
  L.push(`# ${RUN.id}`);
  L.push('');
  L.push(`**판정: ${v}**`);
  L.push('');
  L.push('## 실행 정보');
  L.push('');
  L.push('| 항목 | 값 |');
  L.push('|---|---|');
  L.push(`| 실행 일시 | ${new Date().toISOString()} |`);
  L.push(`| 측정 대상 API | \`${RUN.api}\` |`);
  L.push(`| 목표 도착률 | ${RUN.rate} req/s |`);
  L.push(`| 워밍업 / 측정 | ${RUN.warmup} / ${RUN.duration} |`);
  L.push(`| 머신 | ${RUN.machine} |`);
  L.push(`| 앱 실행 방식 | ${RUN.appMode} |`);
  L.push(`| DB 위치 | ${RUN.dbMode} |`);
  L.push(
    `| DB 크기 / 버퍼풀 | ${RUN.dbSizeMb} MB / ${RUN.dbPoolMb} MB (배율 ${RUN.dbRatio}) |`
  );
  L.push(`| Git commit | ${RUN.commit} |`);
  L.push(`| 변경 사항 | ${RUN.note || '없음 (baseline)'} |`);
  L.push('');
  L.push('## 측정 결과 (워밍업 구간 제외)');
  L.push('');
  L.push('| 지표 | 값 |');
  L.push('|---|---:|');
  L.push(`| 요청 수 (측정 구간) | ${s.reqs === null ? 'n/a' : s.reqs} |`);
  L.push(`| 실제 RPS (측정 구간) | ${fmt(s.rps)} |`);
  L.push(`| 평균 응답시간 | ${fmt(s.avg)} ms |`);
  L.push(`| p50 | ${fmt(s.med)} ms |`);
  L.push(`| p90 | ${fmt(s.p90)} ms |`);
  L.push(`| p95 | ${fmt(s.p95)} ms |`);
  L.push(`| p99 | ${fmt(s.p99)} ms |`);
  L.push(`| 최대 | ${fmt(s.max)} ms |`);
  L.push(`| 서버 처리 시간 p95 (http_req_waiting) | ${fmt(s.waiting)} ms |`);
  L.push(`| 오류율 | ${fmt(s.failRate === null ? null : s.failRate * 100)} % |`);
  L.push(`| dropped_iterations | ${s.dropped === null ? 'n/a' : s.dropped} |`);
  L.push('');

  const per = collectPerApi(data, apiNames);
  if (per.length > 0) {
    L.push('## API별 결과');
    L.push('');
    L.push('> 혼합 시나리오에서는 전체 합산 p95가 의미 없다.');
    L.push('> 빠른 API가 느린 API를 희석하므로 반드시 API별로 본다.');
    L.push('');
    L.push('| API | 요청 수 | 평균 | p95 | p99 | 서버 p95 | 오류율 |');
    L.push('|---|---:|---:|---:|---:|---:|---:|');
    for (const p of per) {
      if (p.reqs === null) continue;
      L.push(
        `| \`${p.name}\` | ${p.reqs} | ${fmt(p.avg, 1)} ms | **${fmt(p.p95, 1)} ms** | ${fmt(
          p.p99,
          1
        )} ms | ${fmt(p.waiting, 1)} ms | ${fmt(p.failRate === null ? null : p.failRate * 100, 2)} % |`
      );
    }
    L.push('');
    L.push('> 서버 p95 = http_req_waiting(TTFB). p95와 서버 p95의 차이가 크면');
    L.push('> 서버가 아니라 요청 본문 전송(업로드)에 시간이 쓰인 것이다.');
    L.push('');
  }

  L.push('## 기준 판정');
  L.push('');
  L.push('| 결과 | 지표 | 기준 |');
  L.push('|---|---|---|');
  for (const r of rows) {
    L.push(`| ${r.ok ? '✅' : '❌'} | \`${r.metric}\` | \`${r.expr}\` |`);
  }
  L.push('');
  if (RUN.dbRatio !== 'unknown' && Number(RUN.dbRatio) < 1.0) {
    L.push('> ⚠️ **DB 크기가 버퍼풀보다 작다(배율 < 1.0)** — 데이터가 전부 메모리에');
    L.push('> 올라가 디스크 I/O가 발생하지 않는다. 인덱스·캐시 개선의 효과가');
    L.push('> 측정되지 않는 조건이므로, 이 실행으로 인덱스 라운드를 판정하지 말 것.');
    L.push('');
  }

  L.push('## Grafana에서 함께 확인할 것');
  L.push('');
  L.push('- [ ] HikariCP active / pending 시계열');
  L.push('- [ ] Tomcat busy threads');
  L.push('- [ ] JVM 힙 사용량 및 GC pause');
  L.push('- [ ] process CPU 사용률 (85% 이상 지속 여부)');
  L.push('- [ ] k6 프로세스 CPU (생성기 포화 여부)');
  L.push('- [ ] DB 디스크 읽기 델타 — 실행 전/후 `backend/scripts/perf-db-snapshot.sql`');
  L.push('      (Innodb_buffer_pool_reads 차이 × 16KB, 최근 히트율 HIT_RATE)');
  L.push('');
  L.push('## 분석');
  L.push('');
  L.push('- 어느 지표가 먼저 기준을 넘었는가:');
  L.push('- 그렇게 판단한 근거 (어떤 시계열이 먼저 올라갔는가):');
  L.push('- 다음 개선 후보:');
  L.push('');
  return L.join('\n');
}

/**
 * 각 스크립트에서 그대로 re-export 해서 쓴다.
 *   export { handleSummary } from './lib/run.js';
 *
 * 결과는 results/ 아래에 저장된다. 실행 전에 디렉토리를 만들어 둘 것.
 *   New-Item -ItemType Directory -Force results
 */
export function handleSummary(data) {
  return makeHandleSummary(null)(data);
}

/**
 * 혼합 시나리오처럼 여러 API가 동시에 도는 경우에 쓴다.
 * apiNames에 넘긴 name 태그별로 p95를 따로 뽑아준다.
 *
 *   export const handleSummary = makeHandleSummary(['GET_markers', 'GET_memory_list', ...]);
 */
export function makeHandleSummary(apiNames) {
  return function (data) {
    const out = {};
    out['stdout'] = renderText(data, apiNames);
    out[`results/${RUN.id}.md`] = renderMarkdown(data, apiNames);
    out[`results/${RUN.id}.json`] = JSON.stringify(data, null, 2);
    return out;
  };
}
