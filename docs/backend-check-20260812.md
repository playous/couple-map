# 백엔드 전체 점검 — 2026-08-12 (최종)

병렬 점검 에이전트 6개(friend / map / auth·login·jwt / memory·mediafile / user·global·s3 / k6 회귀검증)의
결과를 중복 제거하여 통합했다. 같은 결함을 여러 에이전트가 독립적으로 발견한 경우 교차 확인된 것으로 표기했다.

- 기준 코드: `develop` (커밋 전 로컬 변경 포함 — B1/B2/C2 수정 반영 상태)
- 이전 성능 감사(`audit-20260812.md`)에서 이미 다룬 항목은 제외. 이 문서는 **정확성·보안·데이터 무결성** 점검이다.
- 각 항목의 `파일:라인`은 점검 시점 기준.

---

## 1. 치명 (🔴) — 기능이 깨지거나 데이터가 새는 것

### 1-1. 회원 탈퇴가 영구 불가능해지는 FK 잔존 — `map_members.inviter_id` ★3중 교차확인

- `MapMember.java:30-32` — `@JoinColumn(name="inviter_id")` FK, 정리 코드 없음
- `MapMemberRepository.java:55-57` — `deleteAllByUserId`는 `mm.user.userId` 기준만 삭제
- `UserServiceImpl.java:148` — `userRepository.delete(user)`에서 FK 위반

**재현**: A(EDITOR)가 남의 지도에 친구 B를 초대(`MapServiceImpl.java:174` — EDITOR도 초대 가능,
`:190`에서 inviter=A 저장) → A가 탈퇴 → A의 멤버 행만 삭제되고 `inviter_id=A` 행 잔존 →
`DataIntegrityViolationException`(미처리 → 500) + **전체 롤백. 재시도해도 100% 동일 실패 = 영구 탈퇴 불가**.

FK가 없는 스키마라면 대신 dangling inviter가 남아 `MapInvitationDto.java:26`
`getInviter().getNickname()`에서 초대 목록 조회가 500이 된다. 어느 쪽이든 깨진다.

기존 테스트(`UserServiceImplTest.java:106-138`)는 inviter=지도 소유자 케이스만 커버해 이 구멍을 통과시킨다.

**수정**: 탈퇴 5단계쯤에 `DELETE FROM map_members WHERE inviter_id = :userId` (또는 inviter를 nullable로 두고
`UPDATE ... SET inviter_id = NULL`) 추가 + inviter≠소유자 케이스 통합 테스트.

### 1-2. 탈퇴 트랜잭션 안의 Redis 토큰 선삭제 — 롤백 시 강제 로그아웃 + 계정 잔존

- `UserServiceImpl.java:137` — `refreshTokenRepository.deleteById(...)`

Redis(`@RedisHash`)는 JPA 트랜잭션에 참여하지 않아 **즉시 커밋**된다. 1-1(또는 다른 이유)로 뒤 단계에서
롤백되면 RDB는 원복되지만 리프레시 토큰은 이미 삭제 → 탈퇴는 실패했는데 사용자는 로그아웃당한다.
git 이력의 `c31f4cc "회원 탈퇴 실패 시 로그아웃되지 않도록"`은 프론트만 고친 것.

**수정**: `TransactionSynchronization.afterCommit`으로 Redis 삭제를 커밋 이후로 이동.
(B2에서 정리한 원칙과 동일 — "Redis는 롤백이 없으므로 RDB 커밋이 확정된 뒤에 만진다")

### 1-3. PENDING(수락 전) 멤버가 지도의 모든 추억·사진·좌표를 열람 ★2중 교차확인 — 프라이버시 구멍

- 역할 무검증 3곳: `MemoryServiceImpl.java:100-101`(목록), `:127-128`(마커), `:230-231`(상세/수정/삭제 전단)
- PENDING을 배제하는 곳: `MapServiceImpl.java:139/158/243`, 캘린더 `MemoryServiceImpl.java:247`
  (`List.of(OWNER, EDITOR)` + 전용 테스트 존재)

초대는 `map_members`에 role=PENDING 행을 INSERT하는 구조라, 행 존재만 확인하는 위 3곳은
수락 전 사용자를 통과시킨다. `GET /api/maps/{id}/memories/markers`로 **집·근무지 등 위치 이력 전량**이
새어나간다. 같은 사용자에게 지도 상세는 403, 추억 목록은 200 — 인가 기준이 서로 모순.

**수정**: 멤버 검증을 `role != PENDING` 조건의 공용 헬퍼 하나로 통일. (7절 구조 문제 참고)

### 1-4. 닉네임 미설정 유저가 친구가 되면 상대의 친구 목록 전체가 비어버림

- `User.java:32` nickname nullable → `FriendInfoDto.java:19` null 통과 →
  Flutter `friend_repository.dart:20` `json['nickname'] as String` non-null 캐스트 → TypeError →
  `friend_screen.dart:42` `catch (_)`가 삼켜 "아직 친구가 없어요" 표시.
- 백엔드에 "닉네임 설정 완료" 게이트가 없다 (`isNicknameSet` 클레임은 힌트일 뿐 `/api/friend/**`를 막지 않음).
- 같은 위험: `FriendPendingInfoDto.java:22`, `FriendRequestResponseDto.java:15`.

**수정**: DTO에서 null 닉네임 대체값 제공 또는 닉네임 미설정 유저의 친구 기능 게이트.

### 1-5. 초대 수락이 지도명 유일성 검증을 우회 → 이후 그 지도는 수정 영구 불가

- 검증은 create(`MapServiceImpl.java:55-57`)/update(`:117-119`)에만 있고 accept(`:202-218`)에 없음.
- 중복 판정 쿼리(`MapMemberRepository.java:30-42`)가 PENDING을 제외하는 것과 결합:
  A가 "여행" 지도에 B 초대 → B가 직접 "여행" 생성(통과) → B 수락 → 동명 2개 →
  이후 `PUT`은 이름을 안 바꿔도 `MAP_NAME_DUPLICATED` 409 → **설명·배경도 영구 수정 불가**.

**수정**: accept 시 이름 중복 검사, 그리고 update의 중복 검사에서 자기 자신 제외.

---

## 2. 높음 (🟠)

| # | 결함 | 위치 | 요지 |
|---|---|---|---|
| 2-1 | **동영상 업로드가 구조적으로 전부 실패** | `application.yml` `max-file-size: 5MB` vs `S3ServiceImpl.java:27` `MAX_MEDIA_FILE_SIZE=100MB` | 멀티파트 단계에서 5MB 초과가 잘려 100MB 분기는 죽은 코드. video/audio 허용 의도(`:38-47`)가 동작 안 함. max-request-size는 110MB로 설정돼 있어 의도가 5MB가 아니었음이 드러남 |
| 2-2 | **업로드 실패 시 S3 고아 객체 — 보상 없음** | `MemoryServiceImpl.java:86-91`(create), `:199-203`(update) | 파일별 "업로드→엔티티" 루프에서 k번째 실패 시 롤백돼도 1..k-1 S3 객체는 어디에도 기록 안 됨. 클라이언트가 마지막 파일만 거부 대상으로 넣으면 **의도적으로** 고아 생성 가능(요청당 최대 ~100MB). FileCleanupService(아웃박스)가 있는데 삭제 경로에만 쓰임 → **presigned 전환의 ISSUED 상태 설계와 합류할 것** |
| 2-3 | **위조 refresh 토큰 → 401이 아니라 500** | `JWTUtil.java:50-62` | `isExpired`가 `ExpiredJwtException`만 catch. Signature/Malformed는 탈출 → 미처리 500. `/api/auth/refresh`는 permitAll이라 **누구나 무한 5xx 생성 가능** = 측정 오염원. `JWTFilter.java:70`은 정확히 잡는데 refresh만 방어 비대칭 |
| 2-4 | **RestTemplate 타임아웃 전무 + @Transactional 안 외부 호출** | `AppConfig.java:13-15`, `LoginServiceImpl.java:54,57` | 소셜 로그인 1건이 카카오 왕복 내내 Tomcat 스레드 + DB 커넥션 1개 점유. permitAll + 레이트리밋 없음 → 제공자 장애 = 스레드 200개 전면 고갈. `ResourceAccessException` catch는 타임아웃이 없으면 발동하지 않는 죽은 방어. **부하 테스트는 dev login을 써서 이 병목이 측정에 안 잡힘** |
| 2-5 | **신규 가입 동시성 2종 → 500** | `LoginServiceImpl.java:116-128`, `FriendCodeGenerator.java:21` | (a) findByProviderId→save 비원자: 동시 최초 로그인 2건이 UNIQUE 위반. (b) friendCode 36^5 공간, 재시도 없음: N=1,000에서 0.8%, N=9,200에서 50% 누적 충돌 → 간헐 가입 실패 |
| 2-6 | **LOGIN_PROVIDER_MISMATCH 미구현 → 동일 이메일 계정 중복 생성** | `LoginErrorCode.java:12`(선언만), `LoginServiceImpl.java:114-133` | 코드베이스에서 유일하게 throw되지 않는 에러코드. 같은 이메일로 kakao/google 각각 가입하면 계정이 갈라짐 |
| 2-7 | **setNickname TOCTOU → 409 대신 500** | `UserServiceImpl.java:82-86` | check-then-act. 같은 패턴을 friendship(`:52`)·초대(`:192-197`)는 flush+catch로 방어하는데 닉네임만 누락. prod `ddl-auto: validate`는 unique 인덱스를 검증하지 않아 인덱스 부재 시 중복 영구 저장 |
| 2-8 | **썸네일이 IMAGE 필터 없이 최소 order 행** | `MediaFileRepository.java:21-22`, `MemoryServiceImpl.java:110-115`, `:255-260` | 오디오/비디오 URL이 thumbnailUrl로 나가고 Flutter `Image.network`(errorBuilder 없음)가 깨짐. **주의: audit D5의 "displayOrder=1로 좁히기"를 그대로 적용하면 악화 — 반드시 `type=IMAGE` + `MIN(display_order)` 조합으로** |
| 2-9 | **좌표·문자열 검증 부재 → DB 오류 500** | `CreateMemoryRequestDto.java:25-37` 등 | `latitude=100` → precision(10,8) 초과 500. placeName/address/category 255자 초과 → truncation 500. lat=91 같은 지구 밖 좌표는 그대로 저장. `@DecimalMin/Max` + `@Size` + 엔티티 length 명시 필요 |
| 2-10 | **친구 삭제·차단·요청 취소 API 전무** | `FriendController.java` (엔드포인트 4개뿐) | 친구를 끊는 유일한 방법이 회원 탈퇴. 끊긴(끊고 싶은) 친구도 영구히 지도 초대 가능. PENDING도 요청자 취소 불가 + 내가 보낸 요청 조회 불가 → 오타 요청이 그 쌍을 무기한 잠금 |
| 2-11 | **OWNER 탈퇴 시 타 멤버의 추억·사진 무통보 하드삭제** | `UserServiceImpl.java:118-128` | B가 올린 사진 30장이 A 탈퇴로 DB/S3에서 영구 소멸. 소유권 이전/사전 경고 정책 필요 (M2의 "양도 API 부재"와 같은 뿌리) |

---

## 3. 중간 (🟡)

**인가·상태 모델**
- **VIEWER 역할 도달 불가 (dead enum)**: accept가 무조건 EDITOR(`MapMember.java:63-65`), 초대에 role 파라미터 없음. `MemoryServiceImpl.java:72`의 VIEWER 분기는 죽은 코드. + VIEWER가 살아나도 캘린더(`:247`)에서만 배제되는 가시성 불일치 존재.
- **수락자 전원이 재초대 권한 → 권한 무한 확산**: OWNER/EDITOR 모두 초대 가능 + 인원·카테고리 정원 검증 0 (Couple 지도 3인 이상 가능, Solo 지도에도 초대 가능). 도메인 규칙이 프론트에만 존재.
- **초대 취소/멤버 추방/탈퇴/소유권 양도 경로 전무**: PENDING 행이 unique(map_id,user_id) 슬롯을 영구 점유, 멤버 목록에도 안 보여 존재 확인 불가.
- **교차 친구 요청 미처리**: A→B PENDING에서 B가 A 코드 입력 → 양방향 OR 쿼리에 걸려 409 + "이미 친구요청을 **보낸** 사용자입니다"(사실과 반대). 자동 수락 또는 안내 분기 필요.

**파일 정리·S3**
- **S3 실패 원인 소실**: `S3ServiceImpl.java:99-102`가 cause 체이닝 없이 재던져 `file_cleanup_task.last_error`가 항상 같은 문자열. 영구 실패(IAM/버킷)와 일시 실패(네트워크)가 동일 취급돼 FAILED 사후 분류 불가. → `BaseException(ErrorCode, Throwable)` 오버로드 추가(B1 후속과 동일 처방).
- **배치 루프 태스크 격리 없음**: `FileCleanupService.java:42-44` — REQUIRES_NEW 커밋 실패가 전파되면 잔여 태스크 전체가 다음 cron(24h)까지 방치. try/catch로 건 단위 격리.
- **updateProfileImage 새 키 보상 없음**: `UserServiceImpl.java:53-58` — 커밋 실패 시 새 S3 객체가 영구 고아 (옛 키 cleanup 예약 시점은 올바름). `MapServiceImpl.java:126-130` 배경 이미지도 동일 구조. 2-2와 같은 뿌리.

**검증·API 계약**
- **deleteFileIds 중복 ID → 정상 요청이 400 오탐** + 개수 상한 없음(IN 절 1만 개 가능 — C2에서 막은 공격면이 다른 문에 잔존). `MemoryServiceImpl.java:173-178`, Set 정규화 + `@Size` 필요.
- **placeName만 단독 갱신 가능** → placeName/address/좌표가 서로 다른 장소를 가리키는 상태가 API로 만들어지고 되돌릴 경로 없음(좌표 수정 API 부재). `Memory.java:89-95`. 4개 필드 세트 갱신 또는 서버 권위로 잠금. **주의: 세트 갱신을 택하면 k6 editFunc 멱등성 재검토 필요.**
- **displayOrder nullable + 언박싱 비교** → NULL 행 존재 시 NPE 500 (`MediaFile.java:46-47`, `MemoryServiceImpl.java:190-194`). presigned 전환으로 order 권위가 클라이언트로 이동하면 실현 경로가 열림. `nullable=false` + `COALESCE(MAX(...))` 쿼리로.
- **허용 타입 이중 목록 불일치**: `getMediaFileType`(`image/*` 등 접두사)은 S3 화이트리스트 7종보다 넓어 거의 도달 불가한 분기. HEIC(iOS 기본 포맷) 거부 + "JPG, JPEG, PNG만"이라는 거짓 메시지 → iOS 정상 흐름 차단.
- **에러 메시지 불일치 3곳**: 미디어 경로에서 "JPG/JPEG/PNG만"·"5MB 초과 불가"(실제 의도 100MB), "친구 아님"에 `INVALID_FRIENDSHIP_ID`(400) 재사용(전용 `NOT_FRIENDS` 403 필요).
- **캘린더 year·비숫자 파라미터**: 500은 안 나지만(확인 완료) Spring 기본 400 봉투가 `ApiResponse` 형식이 아니라 Flutter가 빈 스낵바 표시. `@Min/@Max` + `ConstraintViolationException` 핸들러.
- **friendId 필드가 DTO마다 다른 의미**(friendshipId ↔ userId), 친구 코드 trim/대문자 정규화 없음(붙여넣기 400).

**동시성·기타**
- **소셜 응답 파싱 500 경로 3개**: null body NPE, 미지원 provider `return null`, 이메일 동의 철회(카카오에서 흔함) 시 `IllegalStateException` → 500 (400이어야 함).
- **JWT 요청당 5~6회 파싱**: 850rps면 초당 ~4,250회 HMAC 검증. `parseClaims` 1회로 통합 → CPU 46% 서사와 직결되는 개선 카드.
- **JWT에 실명/이메일 클레임 — 소비처 0곳**: PII 노출면 + 헤더 크기만 증가. 제거 권장.
- **accept/reject 동시 탭 last-write-wins**(`@Version` 없음), **지도 삭제와 accept 경합 → StaleStateException 500**.
- **Redis 커맨드 타임아웃 미설정**(Lettuce 기본 60s), **목록 조회들 ORDER BY 없음**(순서 비결정), **없는 mapId 응답이 403/404 API마다 불일치**, **403/400·403/404 차이로 ID 열거 가능**(경미).
- **bulk @Modifying에 flush/clear 옵션 없음** — deleteAccount의 파생 삭제와 bulk DML이 같은 행을 중복 대상으로 해 잠재 StaleState. **`deleteAllByUserId`의 2단 implicit join은 MySQL ERROR 1093 가능성** — 1-1 수정 후 통합 테스트로 실제 SQL 실행 필수 확인.

---

## 4. deleteAccount 데이터 흐름 표 (A = 탈퇴자)

| 데이터 | DB 삭제 | S3 예약 | 비고 |
|---|---|---|---|
| A 프로필 이미지 | ✅ | ✅ | |
| A가 쓴 추억 (자기/남의 지도 모두) | ✅ | ✅ | `mf.memory.user.userId` 조건이라 EDITOR로 쓴 것도 커버 — 우려했던 누수 없음 |
| 타인이 A 소유 지도에 쓴 추억 | ✅ | ✅ | **의도치 않은 타인 데이터 손실** (2-11) |
| A 소유 지도·배경·멤버 행 | ✅ | ✅ | |
| A가 받은 초대 / A의 멤버 행 (남의 지도) | ✅ | — | |
| **A가 남의 지도에 보낸 초대 (inviter=A)** | ❌ | — | **FK 위반 → 탈퇴 전체 실패** (1-1) |
| 친구 관계 (양방향) | ✅ | — | requester OR receiver 삭제 — 양호 |
| 리프레시 토큰 (Redis) | ✅ | — | 단, 롤백 불가 (1-2) |
| 발급된 access token | ❌ (≤30분 유효) | — | 전 서비스가 findById로 시작해 404 — 데이터 오염 없음, UX 수준 |

---

## 5. 회귀 검증 (오늘 수정분)

| 수정 | 판정 | 비고 |
|---|---|---|
| B1: GlobalExceptionHandler 4xx warn / 5xx error+스택 | **OK** | ErrorCode 8개 enum 전수 — httpStatus null 불가. 단 B1 처방 3개 중 1개만 이행: `BaseException` 스택 캡처 억제(`super(msg,null,false,false)`)와 async appender는 미적용. 부작용: cause 체이닝이 없어 5xx 스택이 throw 지점부터라 무의미 + 서비스단 중복 error 로그 |
| B2: AuthTokenServiceImpl @Transactional 3개 제거 | **OK** | RDB 접점 0 재확인, 호출자 3곳 전수 — 전파 의존 없음. dev login 경로(부하 테스트 setup)에서 실제 커넥션 절약 확인. 롤백 시맨틱 회귀 없음 |
| C2: 페이징 clamp (page≥0, 1≤size≤100) | **OK** | `?size=0` 500 경로 차단. 전 코드베이스에서 Pageable 사용처는 이 1곳뿐 — `spring.data.web.pageable.max-page-size` 방식은 효과 없음(리졸버 미사용). 기존 호출자 전수(k6 3종 teardown size=100 포함) 상한 비저촉. 잔여: page 상한 없음(깊은 OFFSET + 빈 IN), `?size=abc`는 Spring 기본 400 봉투 |

teardown 3곳이 size=100으로 상한과 동일 — `MAX_PAGE_SIZE`를 낮추려면 k6 3곳도 같이 내려야 한다.

---

## 6. 양호 — 확인 결과 문제 없음 (건드리지 말 것)

- **JWT 코어**: 시크릿 32B fail-fast, HS256 `verifyWith`로 alg 혼동 공격 불가, 필터 무상태(요청당 DB 0회), refresh 검증 순서(만료→카테고리→Redis 대조) 적절. **동시 재발급 경합 없음**(회전 미사용이 의도된 설계 — 단 탈취 시 30일 유효는 설계 노트로).
- **deleteMap / deleteMemory의 삭제 순서와 아웃박스**: `FileCleanupService`가 호출자 트랜잭션에 합류(REQUIRED)해 어느 단계 실패든 cleanup 예약까지 함께 롤백 — "DB는 살았는데 S3만 삭제" 사고 없음.
- **FileCleanupTaskProcessor**: 별도 빈 + REQUIRES_NEW로 자기호출 프록시 함정 없음, 실패 시 markFailed 커밋 확실. S3 없는 키 삭제는 SDK 멱등으로 markDone — 재삭제 안전.
- **친구 도메인 방어**: pairKey UNIQUE + flush + catch(DIVE→409)의 동시 중복 방어, receiver 전용 accept/reject, 자기 요청 차단, 이중 처리 409, 탈퇴 시 양방향 정리.
- **지도 도메인 방어**: 멤버 수 카운트의 PENDING 제외 기준이 3경로 일관, accept/reject의 escalation 차단 완비, reject가 행 삭제라 재초대 가능.
- **memory 방어**: deleteFileIds에 남의 미디어 섞기 정확히 차단(스코프 쿼리+개수 비교+롤백), 타 지도 memoryId는 404로 존재 여부도 은닉, S3 키 UUID라 경로 조작 불가, update의 displayOrder 이어붙이기 정상(auto-flush 의존 포함).
- **JPA 감사**: `@EnableJpaAuditing` 활성 — createdAt null 문제 없음.
- **SecurityConfig**: STATELESS, public 3개 최소화, dev 경로 프로파일 분리, actuator 별도 체인 denyAll, Swagger prod 404. (잔여: `web.ignoring()`이 체인 전체 우회라 permitAll+프로파일 조건이 더 안전 — 낮음)
- **k6 오늘 수정분**: dropped 전역화·upload waiting 셀렉터·run.js DB 행·.gitignore 매칭 전부 정상 확인. (에이전트가 찾은 잔여 결함 4건은 당일 수리 완료 — 아래 7절)

---

## 7. 이 점검에서 함께 수리한 것 (k6 회귀 후속)

| 수리 | 이유 |
|---|---|
| `k6/lib/db-env.ps1` — `-as [double]` 숫자 검증 + `--connect-timeout 3` | 빈 스키마에서 mysql이 리터럴 `NULL`을 출력 → `[double]'NULL'` 캐스트 예외로 **k6 실행 전에 래퍼가 죽는** 경로 차단. "기록 실패가 측정을 막지 않는다" 원칙 복원 |
| `run-mixed.ps1:90` 가드 강화, `run-capacity.ps1`/`run-upload.ps1`에 배율 경고 블록 추가 | 계획 문서의 "래퍼와 결과 md가 경고를 출력한다"가 래퍼 3종 모두에서 사실이 되도록 |
| `k6/legacy/scenario-mixed.js` import `'../helpers.js'` + 사용법 주석 경로 | 폴더 이동으로 모듈 해석이 깨져 실행 불가였음 |
| `results/.gitkeep` + `.gitignore` `!results/.gitkeep` 예외 | 새로 clone하면 results/가 없어 raw `k6 run` 시 3분 측정 후 마지막에 md 쓰기 실패 |
| `docs/load-test-plan.md:158` "SELECT 2개"→"1개" | 실제 쿼리는 1개 (설정값+집계 동시 조회) |

미수리(선택 판단 필요): db-env.ps1의 mysql.exe 탐색이 docker 내 MySQL이면 항상 unknown(docker exec 폴백 필요 여부),
AppMode/DbMode 기본 문자열 불일치(audit A4/A5), audit 문서 내 stale 경로들(날짜 박힌 기록이라 보존 판단 가능).

---

## 8. 우선순위 제안 — 로드맵과의 연결

**즉시 (측정 전에)** — 5xx 생성기는 부하 측정 오염원이므로 R1 이전 수리 권장:
1. 2-3 refresh 500 (JWTUtil catch 확대) — 한 줄 수정
2. 2-9 좌표/문자열 Bean Validation — 어노테이션 추가만

**presigned 트랙에 합류** (같은 작업 범위):
3. 2-2 업로드 고아 보상 — ISSUED 상태 설계에 그대로 포함
4. 2-8 썸네일 IMAGE 필터 — D5(마커/썸네일 프로젝션) 작업 시 함께
5. displayOrder nullable — presigned에서 order 권위가 클라이언트로 이동하기 전에

**E3(벌크삭제/회원탈퇴) 트랙에 합류**:
6. 1-1 inviter FK + 1-2 Redis afterCommit — **E3 실험의 전제 조건** (탈퇴가 완주해야 비교 측정 가능).
   2단 implicit join의 MySQL 실행 검증도 이때.

**기능 결정 필요 (측정과 무관, 사용자 판단)**:
7. 1-3/1-4/1-5, 2-1, 2-5/2-6/2-7, 2-10/2-11, VIEWER·정원·취소/추방/양도 API — 도메인 정책이 걸린 것들.
