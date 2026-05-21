# 파라미터 호환성 가이드

> [README.md](../README.md) Step 2 / Step 6 의 상세 참조 문서.
> BLUE (8.0) 와 GREEN (8.4) 의 서버 파라미터 통과 조건 / 의미 / 미통과 시 대응을 정리합니다.

---

## 1. 분류

| 분류 | 의미 | 대표 변수 |
|---|---|---|
| **고정/필수** | Azure Flex 기본값이자 Data-in Replication 작동에 필수. 변경 불가/불필요 | `gtid_mode`, `enforce_gtid_consistency`, `binlog_format`, `binlog_row_image`, `log_bin` |
| **BLUE = GREEN 일치 필수** | 다르면 데이터 의미가 변형됨. 일부는 서버 생성 후 변경 불가 | `lower_case_table_names`, `character_set_server`, `collation_server`, `time_zone`, `transaction_isolation`, `innodb_strict_mode`, `sql_mode` |
| **운영용 가변** | 운영 정책에 따라 조정 | `binlog_expire_logs_seconds`, `event_scheduler` |
| **충돌 금지** | BLUE 와 절대 같으면 안 됨 | `server_uuid` (`server_id` 도 권장) |
| **버전별 차이** | 8.4 에서 제거/추가됨 | `default_authentication_plugin` (제거), `authentication_policy` (신규) |

---

## 2. 변수별 상세

### 2.1 고정/필수 (Azure Flex 기본값)

| 변수 | 통과 조건 | 의미 | 미통과 시 대응 |
|---|---|---|---|
| `gtid_mode` | `ON` | Data-in Replication 의 기준 좌표 | Azure 파라미터로 ON (대부분 기본 ON) |
| `enforce_gtid_consistency` | `ON` | GTID 안전성 보장 (non-transactional DDL 금지) | ON 설정 후 재시작 |
| `binlog_format` | `ROW` | row 단위 변경 캡처. statement-based 보다 안전 | Azure Flex 는 기본 ROW, 변경 불가 |
| `binlog_row_image` | `FULL` | row-based replication 의 안전성을 높임 (전 컬럼 이미지 기록). PK 없는 테이블은 별도 대응 필요 → §2.6 참조 | Azure Flex 기본 FULL |
| `log_bin` | `ON` | binlog 자체 활성화 | Azure Flex 기본 ON |

### 2.2 BLUE = GREEN 일치 필수

| 변수 | 통과 조건 | 의미 / 다르면 무슨 일이? | 미통과 시 대응 |
|---|---|---|---|
| `lower_case_table_names` | BLUE 와 동일 (Linux 기본 = `1`) | 테이블/DB 이름 대소문자 처리. 다르면 같은 테이블을 못 찾음 | **GREEN 생성 시점에 동일 값으로** — 이후 변경 불가 |
| `character_set_server` | BLUE 와 동일 (`utf8mb4` 권장) | 신규 객체/임시 테이블의 기본 charset. 다르면 한글/이모지 깨짐, JOIN 시 collation mismatch | Azure 파라미터로 변경 |
| `collation_server` | BLUE 와 동일 (`utf8mb4_0900_ai_ci` 등) | 문자열 비교/정렬. 다르면 동일 문자열 비교 결과 차이, 인덱스 미사용, ORDER BY 결과 변경 | Azure 파라미터로 변경 |
| `time_zone` | BLUE 와 동일 | `TIMESTAMP` 컴럼 저장값에 영향. 다르면 시간차만큼 어긋남 | Azure Flex 기본 `+00:00`. Azure 파라미터로 변경 |
| `transaction_isolation` | BLUE 와 동일 (`REPEATABLE-READ` 기본) | 락/팬텀 동작. 다르면 같은 SQL 의 결과/락 동작 변화 → 앱 회귀 | Azure 파라미터로 변경 |
| `innodb_strict_mode` | BLUE 와 동일 | DDL 검증 수준. 다르면 cutover 후 DDL 거부 가능 | Azure 파라미터로 변경 |
| `sql_mode` | BLUE 와 동일 | 쿼리 동작 전반 (zero-date, division by zero 등) | 8.4 는 `NO_AUTO_CREATE_USER` 자동 제거됨 — 그대로 같이 정렬됨 |

### 2.3 운영용 가변

| 변수 | 권장값 | 의미 | 비고 |
|---|---|---|---|
| `binlog_expire_logs_seconds` | `604800` (7일) 이상 | binlog 보존 기간. dump → load → CDC 안정화 기간을 모두 포괄해야 함 | Azure Flex 기본 `0` 은 **무제한 보존이 아니라 handle 이 free 되는 즉시 삭제 가능** 을 의미. 반드시 명시 상향 권장 (대용량은 `1209600` 이상 검토) |
| `event_scheduler` | GREEN load 중 `OFF`, cutover 시 `ON` | event 가 중복 실행되는 것 방지 | Azure 파라미터로만 변경 가능 |

### 2.4 충돌 금지

| 변수 | 조건 | 다르면? |
|---|---|---|
| `server_uuid` | BLUE ≠ GREEN | 같으면 GTID 좌표 충돌 → replication 즉시 깨짐. Azure 가 자동 할당하므로 충돌은 드물지만 반드시 확인 |
| `server_id` | BLUE ≠ GREEN | 같으면 일부 replication 동작에 영향. Azure 자동 할당 |

### 2.5 8.4 신규 / 제거

| 변수 | 변화 | 대응 |
|---|---|---|
| `default_authentication_plugin` | **8.4 에서 제거** | Upgrade Checker 경고 무시. 8.4 에서는 `authentication_policy` 가 인증 관련 정책 변수로 별도 존재 (단, 1:1 대체는 아님 — 아래 참조) |
| `authentication_policy` | **8.4 신규 (MFA factor 정책)** | 계정 생성/변경 시 MFA factor 와 허용 plugin 을 제한하는 정책. **plugin 을 enable 하는 수단이 아님**. 기본값 `'*,,'` 그대로 유지 가능. `mysql_native_password` 사용 가능 여부는 `information_schema.plugins` 의 `plugin_status` 로 확인 — 상세 → [authentication_plugins.md](authentication_plugins.md) |

### 2.6 PK 없는 테이블 / GIPK 주의

`binlog_row_image=FULL` 은 row 이미지를 전부 기록하지만, **PK 없는 InnoDB 테이블이 replication 에서 안전함을 보장하지는 않습니다**. Primary Key 는 Data-in Replication 의 hard requirement 는 아니지만, Microsoft 공식 문서는 source 의 모든 테이블에 명시적 Primary Key 를 둘 것을 권장하며, PK 가 없으면 row-level lookup 비용 때문에 **replica 의 적용 속도 저하 (replication slowness)** 가 발생할 수 있다고 설명합니다. UNIQUE index 존재 여부와 무관하게 PK 없는 테이블은 사전 검토 대상입니다.

또한 Azure Database for MySQL Flexible Server 8.0+ 는 `sql_generate_invisible_primary_key (GIPK)` 가 기본 ON 으로, PK 가 없는 InnoDB 테이블에 자동으로 invisible PK 컬럼이 추가됩니다. Data-in Replication 환경에서 GIPK 가 활성화되어 있으면 다음 시나리오에서 충돌 가능:

- BLUE 와 GREEN 의 GIPK 설정이 다르면 같은 테이블의 컬럼 구조가 어긋남 (GIPK 컬럼 유무)
- cutover 후 GREEN 에서 해당 테이블에 직접 PK 를 추가하거나 `AUTO_INCREMENT` / 파티션 DDL 을 적용할 때 GIPK 와 충돌
- dump 단계에서 GIPK 컬럼이 포함된 채 export 되어 target schema 와 mismatch 발생 가능

**사전 점검**:

```sql
-- Primary Key 가 없는 InnoDB 사용자 테이블 식별
-- (UNIQUE 인덱스 존재 여부와 무관하게 PK 만을 기준으로 봄 — Microsoft 권장은 "각 테이블에 PK")
SELECT t.table_schema, t.table_name
  FROM information_schema.tables t
  LEFT JOIN information_schema.table_constraints tc
    ON tc.table_schema = t.table_schema
   AND tc.table_name = t.table_name
   AND tc.constraint_type = 'PRIMARY KEY'
 WHERE t.table_schema NOT IN ('mysql','sys','performance_schema','information_schema')
   AND t.table_type = 'BASE TABLE'
   AND t.engine = 'InnoDB'
   AND tc.constraint_name IS NULL
 ORDER BY t.table_schema, t.table_name;

-- BLUE / GREEN 각각에서 GIPK 설정 확인
SHOW VARIABLES LIKE 'sql_generate_invisible_primary_key';
```

**대응**:
- 가능하면 BLUE 에서 명시적 PK 를 추가 후 dump 재수행 (가장 안전)
- 추가가 어려운 경우, BLUE/GREEN 의 `sql_generate_invisible_primary_key` 값을 **반드시 동일하게 맞춤** 후 cutover 후의 DDL 영향 검토

---

## 3. 점검 쿼리 (BLUE / GREEN 동일)

```sql
SHOW VARIABLES WHERE Variable_name IN (
  'version',
  'server_id',
  'server_uuid',
  'gtid_mode',
  'enforce_gtid_consistency',
  'binlog_format',
  'binlog_row_image',
  'log_bin',
  'lower_case_table_names',
  'binlog_expire_logs_seconds',
  'character_set_server',
  'collation_server',
  'time_zone',
  'transaction_isolation',
  'innodb_strict_mode',
  'sql_mode',
  'default_authentication_plugin',   -- BLUE 에만 존재
  'authentication_policy',           -- GREEN 에만 존재

  'event_scheduler'
);
```

---

## 4. BLUE ↔ GREEN 파라미터 일괄 비교 (Azure CLI)

```bash
RG=<resource-group>
BLUE=<blue-name>
GREEN=<green-name>

az mysql flexible-server parameter list -g $RG -s $BLUE \
  --query "[].{name:name,value:value}" -o tsv | sort > blue-params.tsv

az mysql flexible-server parameter list -g $RG -s $GREEN \
  --query "[].{name:name,value:value}" -o tsv | sort > green-params.tsv

diff blue-params.tsv green-params.tsv
```

diff 결과 처리:
- **무시 가능**: 8.4 에서 제거된 변수, `version*`, `tls_version` 기본값 차이 등
- **확인 필요**: 위 §2.2 일치 필수 변수가 다르게 보일 경우 — Azure 파라미터로 동기화

---

## 5. Azure 파라미터 변경 명령 템플릿

```bash
az mysql flexible-server parameter set \
  -g <resource-group> -s <server-name> \
  --name <parameter-name> --value <value>
```
