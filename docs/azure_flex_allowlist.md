# Azure Flex Allowlist — Upgrade Checker 결과 해석

> [README.md](../README.md) Step 1 의 상세 참조 문서.
> `util.check-for-server-upgrade` 결과에서 **Azure Flex 환경 특성상 무시 가능한 항목**, **조건부 무시 항목**, **반드시 수정해야 할 항목** 을 분류합니다. 본 문서의 표는 **실제 BLUE 8.0 → GREEN 8.4 checker 로그 기준** 입니다.

---

## 1. 분류 원칙

Upgrade Checker 는 일반적인 MySQL 8.0 → 8.4 업그레이드를 가정하므로, Azure MySQL Flex 의 PaaS 모델 (제한된 SUPER 권한 / 일부 sysvar 자동 관리 / Azure 내부 계정) 과 충돌하는 경고를 다수 출력합니다. 이를 3분류로 처리합니다:

1. **Allowlist (무시 가능)** — Azure PaaS 가 알아서 처리하거나 사용자가 손댈 수 없는 항목
2. **Conditional Allowlist (조건부 무시)** — 환경 조건을 확인한 후에만 무시
3. **반드시 수정** — 앱 코드/객체/계정 관련. 무시하면 cutover 후 장애 발생

---

## 2. Allowlist (무시 가능)

다음 항목들은 Azure Flexible Server 8.0 baseline 에서도 재현되는 **PaaS/버전 전환 노이즈** 로 판단합니다. GREEN 8.4 신규 프로비저닝 시 Azure 또는 MySQL 8.4 기본 동작으로 대체되며, BLUE 8.0 의 해당 server parameter 또는 Azure 내부 계정을 GREEN 에 수동 이관하지 않습니다. 따라서 마이그레이션 차단 항목에서 제외합니다.

> ⚠️ 이 allowlist 는 **애플리케이션 계정 / 클라이언트 TLS 호환성 / routine·view·trigger·event DEFINER 검증을 면제하지 않습니다.** 해당 검증은 §3 (Conditional Allowlist) 및 [definer_handling.md](definer_handling.md) 참조.

### 2.1 Allowlist: 시스템 변수

| 점검 ID | dbObject | 무시 가능한 이유 |
|---|---|---|
| `removedSysVars` | `avoid_temporal_upgrade` | 8.4 GREEN 에 변수 자체 없음 |
| `removedSysVars` | `binlog_transaction_dependency_tracking` | 8.4 에서 WRITESET 강제 / 변수 제거 |
| `removedSysVars` | `expire_logs_days` | `binlog_expire_logs_seconds` 가 대체 (Azure 기본) |
| `removedSysVars` | `log_bin_use_v1_row_events` | v2 row event 표준 (Azure 기본) |
| `removedSysVars` | `master_info_repository` | TABLE 만 지원 (Azure 기본) |
| `removedSysVars` | `profiling_history_size` | Performance Schema 로 대체 |
| `removedSysVars` | `relay_log_info_repository` | TABLE 만 지원 (Azure 기본) |
| `removedSysVars` | `show_old_temporals` | old temporal 자체 제거 |
| `removedSysVars` | `slave_rows_search_algorithms` | HASH_SCAN 강제 (Azure 기본) |
| `removedSysVars` | `transaction_write_set_extraction` | XXHASH64 기본 / 변수 제거 |
| `deprecatedDefaultAuth` | `default_authentication_plugin` | 8.4 에선 변수 자체 제거 ([authentication_plugins.md](authentication_plugins.md)) |
| `sysVarsNewDefaults` | `group_replication_exit_state_action` | Group Replication 미사용 환경에서 무관 (default `READ_ONLY` → `OFFLINE_MODE`) |

### 2.2 Allowlist: Azure 내부 계정

| 점검 ID | dbObject | 무시 가능한 이유 |
|---|---|---|
| `authMethodUsage` | `azure_superuser@127.0.0.1` | Azure 시스템 계정. GREEN 에서 `caching_sha2_password` 로 자동 재생성 |
| `authMethodUsage` | `azure_superuser@localhost` | 동일 |
| `invalidPrivileges` | `'azure_superuser'@'127.0.0.1'` | Azure 시스템 계정. `SET_USER_ID` 권한 자동 조정 |
| `invalidPrivileges` | `'azure_superuser'@'localhost'` | 동일 |

자세한 PaaS 관리 계정 처리는 [authentication_plugins.md](authentication_plugins.md) 참조.

---

## 3. Conditional Allowlist (조건 충족 시 차단 제외)

다음 항목은 migration blocker 는 아니지만, **지정된 검증 조건을 충족한 경우에만 차단 항목에서 제외** 합니다. 검증 결과는 변경심의 기록에 남깁니다.

| 점검 ID | dbObject | 차단 제외 조건 |
|---|---|---|
| `sysvarAllowedValues` | `ssl_cipher` | BLUE 값을 GREEN 에 수동 복사하지 않음 + GREEN 8.4 기본 TLS 설정 사용 + 모든 앱/배치/BI/ETL 클라이언트의 TLS handshake 테스트 통과 |
| `sysvarAllowedValues` | `tls_ciphersuites` | 위와 동일 |
| `sysVarsNewDefaults` | `innodb_log_writer_threads` | default `ON` → `OFF` (vCPU ≤ 32). 기능 blocker 에서 제외하되, cutover 후 write latency / CPU / IOPS 모니터링 + 회귀 없음 확인 |
| `sysVarsNewDefaults` | `innodb_read_io_threads` | default `4` → `MAX(vCPU/2, 4)`. cutover 후 read latency / IOPS 모니터링 + 회귀 없음 확인 |
| `authMethodUsage` | `<admin-user>@%` (예: `sqladmin@%`) | 애플리케이션/배치/ETL 이 이 계정을 사용하지 않음 + 관리 접속 테스트 통과 |
| `invalidPrivileges` | `'<admin-user>'@'%'` | 앱 계정 미사용 + routine/view/event/trigger DEFINER 의존 없음 ([definer_handling.md](definer_handling.md) 검증) |
| `invalidPrivileges` | `'<entra-admin-user>'@'%'` (예: `'administrator@<tenant>'@'%'`) | 앱 계정 미사용 + 관리 접속 테스트 통과 |
| `authMethodUsage` | `syncuser@%` (Data-in Replication 전용) | 8.4 GREEN 에서 동일 user 를 `caching_sha2_password` 로 재생성하여 `CHANGE REPLICATION SOURCE` 에 사용 ([README Step 14](../README.md)) |

---

## 4. 반드시 수정 (allowlist 아님)

### 4.1 앱 객체 / DEFINER

| 경고 카테고리 | 의미 | 처리 |
|---|---|---|
| `routinesSyntaxCheck` | 사용자 정의 routine 에 8.4 와 호환 안 되는 SQL | 해당 routine 수정 |
| `triggersSyntaxCheck` | trigger 본문에 호환 안 되는 SQL | 해당 trigger 수정 |
| `viewsSyntaxCheck` | view 정의에 호환 안 되는 SQL | view 재작성 |
| DEFINER 가 존재하지 않는 계정 | cutover 후 호출 시 ERROR 1449 | [definer_handling.md](definer_handling.md) |
| `partitionedTables` | 8.4 에서 변경된 partition syntax | 영향 받은 테이블 재정의 |

### 4.2 코드 / 쿼리

| 카테고리 | 처리 |
|---|---|
| `removedFunctions` 중 실제 사용 중 | 코드 수정 (`JSON_OBJECTAGG` 등 대체 함수 사용) |
| `reservedKeywordsCheck` 8.4 신규 예약어 (`MANUAL`, `PARALLEL`, `QUALIFY`, `TABLESAMPLE`) | 식별자로 사용 중인지 확인 → 백틱 처리 또는 rename |
| `sqlMode` 차이로 동작이 바뀌는 쿼리 | 앱 회귀 테스트로 확인 후 수정 |

---

## 5. 결과 처리 절차

1. `errors > 0` → **반드시 마이그레이션 전 수정** (스키마/계정 변경)
2. `warnings` → 영향 분석 후 의사결정 (앱 코드 수정 포함)
3. 모든 변경은 **BLUE 에서 먼저 적용 → 앱 회귀 테스트 → 덤프 진행**
4. Azure 포털 Server upgrade 블레이드의 *Pre-upgrade validation* 보다 MySQL Shell `util.check-for-server-upgrade` 가 더 상세함. **둘 다 실행 권장.**

### 5.1 분류 워크플로우 (jq)

```bash
# 1. 전체 결과 중 문제 있는 check 만
jq '.checksPerformed[] | select(.detectedProblems | length > 0)' ~/upgrade_check_8.4.json

# 2. Error 만
jq '[.checksPerformed[] | .detectedProblems[]? | select(.level=="Error")]' ~/upgrade_check_8.4.json

# 3. 카테고리별 카운트
jq '.checksPerformed[]
    | select(.detectedProblems | length > 0)
    | {id: .id, count: (.detectedProblems | length)}' ~/upgrade_check_8.4.json
```

각 항목의 `id` 를 위 §2~§4 표와 매칭해 분류.

---

## 6. 참고

- [MySQL Shell: Upgrade Checker Utility](https://dev.mysql.com/doc/mysql-shell/9.7/en/mysql-shell-utilities-upgrade.html) — 전체 check id 목록
- [What's new in MySQL 8.4](https://dev.mysql.com/doc/refman/8.4/en/mysql-nutshell.html) — 제거/변경 사항 공식 목록
