# DEFINER 처리 가이드

> [README.md](../README.md) Step 3 의 상세 참조 문서.
> ROUTINE / TRIGGER / VIEW / EVENT 의 DEFINER 가 GREEN 환경에서 어떻게 처리되어야 하는지 정리합니다.

---

## 1. DEFINER 가 왜 문제인가

MySQL routine / view / trigger / event 의 DEFINER 계정이 GREEN 에 존재하지 않으면 호출 시점에 `ERROR 1449 (HY000): The user specified as a definer ('xxx'@'yyy') does not exist` 가 발생합니다.

---

## 2. DEFINER 패턴별 판정 표

| DEFINER 패턴 | 예시 | 양쪽 존재 여부 | 처리 |
|---|---|---|---|
| 운영 owner 계정 | `app_owner@%`, `ecommerce_owner@%` | BLUE = GREEN 동일 | **OK** — 가장 모범적인 패턴 |
| 일반 앱 계정 | `app_rw@%`, `app_batch@%` | BLUE = GREEN 동일 | **OK** |
| 특정 host 로 한정 | `xxx@10.0.0.5` | BLUE 에만 / 또는 host 매칭 안 됨 | `xxx@%` 로 **재정의 권장** |
| GREEN 에 없는 dev 계정 | `dev_user@%`, `tmp_admin@%` | BLUE 만 | **반드시 재정의** — 그대로 두면 ERROR 1449 |
| 삭제된 계정 | `former_employee@%` | 양쪽 모두 없음 | **반드시 재정의** |
| 관리자 계정 | `<관리자>@%` (Entra ID admin / 사용자가 생성한 관리자) | 양쪽 모두 있음 | **OK** but 운영 정책상 routine DEFINER 로는 비권장 |

**검증 쿼리** — GREEN 에서 실행, DEFINER 목록이 실제 `mysql.user` 에 존재하는지 확인. `information_schema.*.DEFINER` 는 `'user'@'host'` 형식이므로 quote/backtick 을 제거해 정규화한 뒤 비교합니다:

```sql
WITH definers AS (
  SELECT definer FROM information_schema.routines
   WHERE routine_schema NOT IN ('mysql','sys','performance_schema','information_schema')
  UNION
  SELECT definer FROM information_schema.triggers
   WHERE trigger_schema NOT IN ('mysql','sys','performance_schema','information_schema')
  UNION
  SELECT definer FROM information_schema.views
   WHERE table_schema NOT IN ('mysql','sys','performance_schema','information_schema')
  UNION
  SELECT definer FROM information_schema.events
   WHERE event_schema NOT IN ('mysql','sys','performance_schema','information_schema')
),
normalized AS (
  SELECT DISTINCT
         definer,
         REPLACE(REPLACE(definer, '`', ''), '''', '') AS account_name
    FROM definers
),
split AS (
  SELECT
         definer,
         LEFT(
           account_name,
           LENGTH(account_name) - LENGTH(SUBSTRING_INDEX(account_name, '@', -1)) - 1
         ) AS definer_user,
         SUBSTRING_INDEX(account_name, '@', -1) AS definer_host
    FROM normalized
)
SELECT n.definer, n.definer_user, n.definer_host
  FROM split n
  LEFT JOIN mysql.user u
    ON u.user = n.definer_user
   AND u.host = n.definer_host
 WHERE u.user IS NULL
 ORDER BY n.definer;
```

> 💡 `LEFT(... , LENGTH - LENGTH(SUBSTRING_INDEX(..., '@', -1)) - 1)` 패턴을 쓰는 이유: account name 의 user part 에 `@` 가 포함될 수 있습니다 (예: Entra 계정 `user@domain.com@%`). `SUBSTRING_INDEX(..., '@', 1)` 로 단순히 첫 `@` 기준으로 자르면 user 가 `user` 로 잘못 잘립니다. 마지막 `@` 를 host 구분자로 보고 그 앞 전체를 user 로 취해야 정확합니다.

결과가 **0건** 이어야 cutover 전 통과 입니다. 각 행은 GREEN 에 존재하지 않는 DEFINER 로, cutover 전에 반드시 생성 / 재정의 대상입니다.

> ⚠️ 패턴 매칭 (`definer NOT REGEXP '^app_'` 등) 으로만 필터링하지 마세요.
> 이미 삭제된 계정, 특정 host 로 한정된 계정, 알 수 없는 prefix 등은 필터를 통과해 버립니다.

---

## 3. 재정의 레시피

### 3.1 VIEW — `CREATE OR REPLACE`

```sql
CREATE OR REPLACE
  DEFINER=`app_rw`@`%`
  SQL SECURITY DEFINER
  VIEW ecommerce.v_xxx AS
  SELECT ...;
```

### 3.2 EVENT — `ALTER`

```sql
ALTER DEFINER=`app_rw`@`%`
  EVENT ecommerce.ev_xxx
  ON SCHEDULE EVERY 1 HOUR
  DO BEGIN ... END;
```

### 3.3 PROCEDURE / FUNCTION — `DROP + CREATE` (ALTER 로 DEFINER 변경 불가)

```sql
-- 원본 정의 확인
SHOW CREATE PROCEDURE ecommerce.sp_xxx\G

-- 드롭 후 재생성
DROP PROCEDURE ecommerce.sp_xxx;

DELIMITER //
CREATE DEFINER=`app_rw`@`%`
  PROCEDURE ecommerce.sp_xxx(IN p_id INT)
  SQL SECURITY DEFINER
  BEGIN
    -- 원본 본문 그대로
  END//
DELIMITER ;
```

### 3.4 TRIGGER — `DROP + CREATE` (ALTER 미지원)

```sql
DROP TRIGGER ecommerce.trg_xxx;

DELIMITER //
CREATE DEFINER=`app_rw`@`%`
  TRIGGER ecommerce.trg_xxx
  BEFORE INSERT ON ecommerce.orders
  FOR EACH ROW
  BEGIN
    -- 원본 본문 그대로
  END//
DELIMITER ;
```

> ⚠️ `SHOW CREATE TRIGGER` / `SHOW CREATE PROCEDURE` 등으로 **본문을 정확히 백업** 후 작업하세요. 본문 누락 시 비즈니스 로직 손실.

---

## 4. 처리 시점 — 사전 vs 사후

| 시점 | 장점 | 단점 |
|---|---|---|
| **BLUE 에서 사전** (Step 3 직후) | 한 번만 작업, GREEN 에 자동 전파 | BLUE 운영에 영향 (DDL → binlog 기록) |
| **GREEN 에서 사후** (cutover 직전) | BLUE 운영 무영향 | GREEN 에만 적용 → 향후 BLUE 롤백 시 다시 작업 필요 |

본 가이드 권장: **BLUE 에서 사전 처리** (replication 으로 GREEN 자동 동기화).

---

## 5. SQL SECURITY DEFINER vs INVOKER

DEFINER 변경 시 `SQL SECURITY` 도 함께 확인:

| 모드 | 실행 권한 | 사용 케이스 |
|---|---|---|
| `DEFINER` | DEFINER 계정의 권한으로 실행 | 일반 사용자가 elevated 권한 필요한 routine 호출 (e.g. 통계 집계, 로깅) |
| `INVOKER` | 호출자 계정의 권한으로 실행 | 일반 SELECT/UPDATE 래퍼 |

→ 가능하면 `SQL SECURITY INVOKER` 로 정의하면 DEFINER 의존성을 줄일 수 있습니다.

---

## 6. 처리 완료 검증 — 0건 확인

처리 완료 후 GREEN 에서 §2 의 **정규화된 검증 쿼리** 를 다시 실행해 결과가 0건인지 확인하세요. 결과 행이 남아 있으면 해당 DEFINER 고유의 재정의 / 계정 생성을 완료한 뒤 재검증.
