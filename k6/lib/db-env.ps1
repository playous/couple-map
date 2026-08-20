# DB 환경 스냅샷 수집 (읽기 전용)
#
# 왜 필요한가:
#   시드 v2(15만/60만 행)의 목적은 "데이터를 InnoDB 버퍼풀보다 크게 만들어
#   디스크 I/O가 발생하는 구간에서 측정하는 것"이다. 그런데
#   innodb_buffer_pool_size는 로컬 MySQL 설정이라 git 밖에 있다.
#   이 값이 바뀌면 모든 라운드 비교가 무효가 되므로 매 실행마다 기록한다.
#
#   2026-08-12 실측 기준: 버퍼풀 128MB / DB 199MB / 배율 1.56
#   배율이 1.0 미만이면 전부 메모리에 올라가 인덱스 개선 효과가 측정되지 않는다.
#
# 실행하는 쿼리는 SELECT 1개뿐이다 (설정값 + information_schema 집계 동시 조회).
# 데이터를 변경하지 않는다.
#
# 비밀번호가 없으면 조용히 'unknown'을 반환한다 — 측정을 막지 않는다.

function Get-DbEnvSnapshot {
    param(
        [string]$DbPassword = '',
        [string]$DbHost = '127.0.0.1',
        [int]$DbPort = 3306,
        [string]$DbUser = 'root',
        [string]$DbName = 'couplemap'
    )

    $result = [ordered]@{ PoolMb = 'unknown'; SizeMb = 'unknown'; Ratio = 'unknown' }

    $pw = if ($DbPassword) { $DbPassword } elseif ($env:MYSQL_PWD) { $env:MYSQL_PWD } else { '' }
    if (-not $pw) { return $result }

    # mysql.exe 탐색: PATH → MySQL Server → Workbench
    $mysqlExe = $null
    $resolved = Get-Command 'mysql.exe' -ErrorAction SilentlyContinue
    if ($resolved) { $mysqlExe = $resolved.Source }
    if (-not $mysqlExe) {
        foreach ($p in @(
            "$env:ProgramFiles\MySQL\MySQL Server 8.0\bin\mysql.exe",
            "$env:ProgramFiles\MySQL\MySQL Workbench 8.0 CE\mysql.exe"
        )) {
            if (Test-Path -LiteralPath $p) { $mysqlExe = $p; break }
        }
    }
    if (-not $mysqlExe) { return $result }

    $query = @"
SELECT ROUND(@@innodb_buffer_pool_size/1024/1024, 1) AS pool_mb,
       ROUND(SUM(data_length+index_length)/1024/1024, 1) AS db_mb,
       ROUND(SUM(data_length+index_length)/@@innodb_buffer_pool_size, 2) AS ratio
FROM information_schema.tables WHERE table_schema='$DbName';
"@

    $prevPwd = $env:MYSQL_PWD
    $env:MYSQL_PWD = $pw
    try {
        $out = $query | & $mysqlExe --host $DbHost --port $DbPort --user $DbUser --connect-timeout 3 --batch --skip-column-names $DbName 2>$null
        if ($LASTEXITCODE -eq 0 -and $out) {
            $cols = ($out | Select-Object -First 1) -split "`t"
            if ($cols.Count -ge 3) {
                # 숫자 검증 필수 — 스키마가 비어 있으면 mysql이 리터럴 'NULL'을
                # 출력하는데, 그대로 저장하면 호출부의 [double] 캐스트가 터져
                # k6 실행 전에 래퍼가 죽는다. 숫자가 아니면 unknown 유지.
                $p = $cols[0].Trim() -as [double]
                $s = $cols[1].Trim() -as [double]
                $r = $cols[2].Trim() -as [double]
                if ($null -ne $p -and $null -ne $s -and $null -ne $r) {
                    $result.PoolMb = $cols[0].Trim()
                    $result.SizeMb = $cols[1].Trim()
                    $result.Ratio = $cols[2].Trim()
                }
            }
        }
    } catch {
        # 조회 실패는 측정을 막지 않는다 — unknown으로 남긴다
    } finally {
        if ($null -eq $prevPwd) {
            if (Test-Path Env:\MYSQL_PWD) { [Environment]::SetEnvironmentVariable('MYSQL_PWD', $null) }
        } else {
            $env:MYSQL_PWD = $prevPwd
        }
    }

    return $result
}
