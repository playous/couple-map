# 사용자 여정 부하 실행 래퍼 (VU 고정, 닫힌 모델)
#
# 판정 기준은 docs/load-test-plan.md를 따른다.
#   - 판정은 VU 1,000에서만 한다. 아래 단계는 병목이 시작되는 지점을 보는 관찰용이다.
#   - think 배율은 1.0(실제 사람 속도)으로 고정한다. 낮추면 "동시 사용자 N명"의 의미가 흐려진다.
#
# 사용:
#   .\k6\run-journey.ps1 -Vus 5000 -Note baseline -Prometheus
#   .\k6\run-journey.ps1 -Vus 5000 -Note "Hikari 풀 30" -Prometheus
#   .\k6\run-journey.ps1 -Vus 5000 -Note "업로드 빼고 비교" -NoUpload -Prometheus
#
# 프로젝트 루트(couple-map/)에서 실행할 것.

param(
    [Parameter(Mandatory = $true)]
    [int]$Vus,

    [string]$Note = 'baseline',
    [string]$Duration = '2m',
    [string]$Warmup = '60s',
    [string]$BaseUrl = 'http://localhost:8080',

    # think time 배율. 1.0 = 실제 사람 속도. 계획서상 고정값이므로 바꾸면 결과에 명시할 것.
    [double]$Think = 1.0,

    # 파일 업로드를 뺀다. 기본은 포함이다.
    # presigned 전환 후 서버는 발급, 완료 JSON 두 개만 처리하므로 격리할 이유가 없다.
    # 생성기 업링크가 못 버텨 S3 PUT에서 VU가 묶이는 게 확인되면 그때만 쓴다.
    [switch]$NoUpload,

    # 실행 방식이 바뀌면 이 값도 바꿀 것
    [string]$AppMode = 'IntelliJ-local-C2',
    [string]$DbMode = 'local-mysql8',

    # DB 환경 스냅샷 조회용 (읽기 전용 SELECT 1개).
    # 생략하면 $env:MYSQL_PWD를 쓰고, 그것도 없으면 unknown으로 기록된다.
    [string]$DbPassword = '',

    # 생성 데이터를 k6가 정리하게 한다 (기본은 정리하지 않고 cleanup SQL을 쓴다)
    [switch]$Cleanup,
    # Prometheus로 k6 메트릭을 실시간 스트리밍한다.
    [switch]$Prometheus,
    [string]$PrometheusUrl = 'http://localhost:9090/api/v1/write'
)

$ErrorActionPreference = 'Stop'

$cpu = Get-CimInstance Win32_Processor
$ramGb = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 0)
$machine = "$($cpu.Name.Trim()) $($cpu.NumberOfCores)C$($cpu.NumberOfLogicalProcessors)T ${ramGb}GB"

$commit = 'unknown'
try {
    $rev = git rev-parse --short HEAD 2>$null
    if ($LASTEXITCODE -eq 0) {
        $dirty = git status --porcelain 2>$null
        if ($dirty) { $commit = "$rev-dirty" } else { $commit = $rev }
    }
} catch {
    # git이 없으면 unknown 유지
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmm'
$runId = "journey-vu$Vus-$stamp"

New-Item -ItemType Directory -Force results | Out-Null

# DB 환경 스냅샷 — 버퍼풀 대비 데이터 크기는 시드 v3의 전제이므로 매 실행 기록한다
. (Join-Path $PSScriptRoot 'lib\db-env.ps1')
$dbEnv = Get-DbEnvSnapshot -DbPassword $DbPassword

Write-Host ''
Write-Host '════════════════════════════════════════════════════' -ForegroundColor Cyan
Write-Host "  RUN_ID     : $runId"
Write-Host "  동시 사용자: $Vus 명 고정"
Write-Host "  think 배율 : $Think"
Write-Host "  구간       : 워밍업 $Warmup → 측정 $Duration"
Write-Host "  변경사항   : $Note"
Write-Host "  머신       : $machine"
Write-Host "  앱         : $AppMode"
Write-Host "  DB         : $DbMode"
Write-Host "  DB 크기    : $($dbEnv.SizeMb) MB / 버퍼풀 $($dbEnv.PoolMb) MB (배율 $($dbEnv.Ratio))"
Write-Host "  commit     : $commit"
Write-Host '════════════════════════════════════════════════════' -ForegroundColor Cyan

if ($Think -ne 1.0) {
    Write-Host "  경고: think 배율이 $Think 입니다 (기준값 1.0)." -ForegroundColor Yellow
    Write-Host '        가속 사용자 모델이므로 결과와 포폴에 반드시 명시하세요.' -ForegroundColor Yellow
    Write-Host ''
}

if ($dbEnv.Ratio -eq 'unknown') {
    Write-Host '  DB 환경 미기록 — $env:MYSQL_PWD를 설정하면 버퍼풀 대비 크기가 자동 기록됩니다.' -ForegroundColor Yellow
    Write-Host ''
} elseif (($dbEnv.Ratio -as [double]) -ne $null -and [double]$dbEnv.Ratio -lt 1.0) {
    Write-Host "  참고: DB($($dbEnv.SizeMb)MB)가 버퍼풀($($dbEnv.PoolMb)MB)보다 작습니다 (배율 $($dbEnv.Ratio))." -ForegroundColor Yellow
    Write-Host '        데이터가 전부 메모리에 올라가 디스크 I/O가 거의 없는 조건입니다.' -ForegroundColor Yellow
    Write-Host '        인덱스 개선 폭이 작게 나와도 "효과 없음"으로 결론짓지 말고 조건을 병기하세요.' -ForegroundColor Yellow
    Write-Host '        버퍼풀은 기본값을 그대로 씁니다. 이 값을 맞추려고 조정하지 않습니다.' -ForegroundColor Yellow
    Write-Host ''
}

if ($NoUpload) {
    Write-Host '  파일 업로드 제외 (-NoUpload). 조건을 결과에 병기하세요.' -ForegroundColor Yellow
}
Write-Host ''

$uploadFlag = if ($NoUpload) { '0' } else { '1' }

$k6Args = @(
    'run',
    '--env', "BASE_URL=$BaseUrl",
    '--env', "VUS=$Vus",
    '--env', "THINK=$Think",
    '--env', "UPLOAD=$uploadFlag",
    '--env', "DURATION=$Duration",
    '--env', "WARMUP=$Warmup",
    '--env', "RUN_ID=$runId",
    '--env', "API=journey",
    '--env', "RATE=$Vus",
    '--env', "NOTE=$Note",
    '--env', "MACHINE=$machine",
    '--env', "APP_MODE=$AppMode",
    '--env', "DB_MODE=$DbMode",
    '--env', "DB_POOL_MB=$($dbEnv.PoolMb)",
    '--env', "DB_SIZE_MB=$($dbEnv.SizeMb)",
    '--env', "DB_RATIO=$($dbEnv.Ratio)",
    '--env', "COMMIT=$commit"
)

if ($Cleanup) { $k6Args += @('--env', 'CLEANUP=true') }

if ($Prometheus) {
    $env:K6_PROMETHEUS_RW_SERVER_URL = $PrometheusUrl
    # 이 값이 없으면 k6는 p(99)만 보내고 대시보드의 p95 패널이 전부 비어 있게 된다.
    $env:K6_PROMETHEUS_RW_TREND_STATS = 'p(95),p(99),min,max'
    $k6Args += @(
        '--out', 'experimental-prometheus-rw',
        '--tag', "testid=$runId"
    )
    Write-Host "  Prometheus: $PrometheusUrl" -ForegroundColor Cyan
    Write-Host ''
}

$k6Args += 'k6/journey.js'

# PowerShell/Conda 환경에서 PATH 갱신이 늦어도 설치된 k6.exe를 찾는다.
$k6Exe = $null
$resolvedK6 = Get-Command 'k6.exe' -ErrorAction SilentlyContinue
if ($resolvedK6) {
    $k6Exe = $resolvedK6.Source
}
if (-not $k6Exe) {
    $programFilesK6 = Join-Path $env:ProgramFiles 'k6\k6.exe'
    if (Test-Path -LiteralPath $programFilesK6) {
        $k6Exe = $programFilesK6
    }
}
if (-not $k6Exe) {
    throw 'k6.exe를 찾을 수 없습니다. 새 PowerShell에서 k6 version을 먼저 확인하세요.'
}

& $k6Exe @k6Args
$exit = $LASTEXITCODE

Write-Host ''
if ($exit -eq 0) {
    Write-Host "  PASS — 동시 사용자 $Vus 명에서 전 API가 SLO를 지켰습니다." -ForegroundColor Green
} else {
    Write-Host "  FAIL — 동시 사용자 $Vus 명에서 SLO가 깨졌습니다." -ForegroundColor Red
    Write-Host '         results 의 "API별 결과" 표에서 어느 API가 먼저 넘었는지 확인하세요.' -ForegroundColor Red
}
Write-Host ''
Write-Host '  무효 판정 체크 (닫힌 모델에는 dropped_iterations가 없습니다):' -ForegroundColor Cyan
Write-Host '    - 생성기 머신 CPU가 80%를 넘었으면 이 실행은 무효입니다.'
Write-Host '    - Grafana에서 VU가 설정값에 고정돼 있었는지 확인하세요.'
Write-Host ''
Write-Host "  기록: results/$runId.md"
Write-Host ''

exit $exit
