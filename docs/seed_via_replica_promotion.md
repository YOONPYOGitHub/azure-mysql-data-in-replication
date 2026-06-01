# 대안 시딩 — BLUE Read Replica 업그레이드 · promotion 으로 GREEN 구성

> [README.md](../README.md) 의 **Step 7-12 (dump/load 기반 시딩) 대안 경로** 참조 문서.
> `util.dumpInstance` / `util.loadDump` / `gtid reset` 으로 GREEN 을 채우는 대신,
> **BLUE 의 Read Replica 를 8.4 로 in-place 업그레이드한 뒤 promote 해서 GREEN 으로 삼고**,
> promotion 시점 GTID 부터 Data-in Replication 을 잇는 방식입니다.

---

## 1. 언제 사용하나

- BLUE 가 대용량이라 dump/load 의 시간·디스크 비용이 부담될 때
- 이미 물리 복제본(Read Replica)이 존재해, 이를 재활용해 시딩 시간을 줄이고 싶을 때
- dump/load 시점 정합성(`--consistent`)·GTID reset 절차를 생략하고, **Azure 가 관리하는 복제본을 그대로 승격** 하고 싶을 때

> 이 경로를 쓰면 README 의 **Step 7-12 (dump → GTID 추출 → load → GTID reset)** 를 이 문서 절차로 **대체** 합니다.
> 나머지 단계 — Step 1-6 (사전 점검 / 계정 / 파라미터), Step 13 (CA bundle), Step 14-15 (change master + 검증), Step 16-20 (replica / 정합성 / cutover) — 는 README 를 그대로 따릅니다.

---

## 2. dump/load 경로와의 비교

| 항목 | dump/load (README Step 7-12) | 본 문서 (replica promotion) |
|---|---|---|
| GREEN 초기 데이터 | `util.loadDump` 로 적재 | BLUE Read Replica 를 그대로 재사용 (데이터 **이미 보유**) |
| major version 8.0 → 8.4 | GREEN 을 8.4 로 신규 생성 | Read Replica 를 **in-place major upgrade** |
| GTID 기준점 | dump `@.json` GTID → `gtid reset` | **promotion 시점 `gtid_executed`** 가 자동 기준점 (reset 불필요) |
| 소요/비용 | dump 크기·load 시간·`/data` 디스크 | 복제본 초기 sync + 업그레이드 시간 |
| 데이터 정합성 보장 | `--consistent=true` 스냅샷 | Azure 관리 복제(이미 동기화된 상태) |

---

## 3. 전체 흐름 (테스트 검증 순서)

```
BLUE 8.0 Primary
  ├─ Read Replica #1 (운영)
  ├─ Read Replica #2 (운영)
  └─ Read Replica #SEED  ← (1) 시딩용으로 1대 추가
          │ (2) 8.4 로 major version in-place upgrade
          │ (3) promotion (standalone 8.4 primary 로 승격) → 이 서버가 GREEN
          ▼
      GREEN 8.4 Primary
          │ (4) HA = ZoneRedundant 구성
          │ (5) Data-in Replication 구성 (BLUE → GREEN, promotion GTID 부터)
          ├─ (6) Read Replica #1
          └─ (6) Read Replica #2
```

| 순서 | 작업 | 실행 위치 | README 대응 |
|---|---|---|---|
| 1 | BLUE 에 시딩용 Read Replica 1대 추가 | 💻VM → ☁️Azure | (Step 7-9 대체) |
| 2 | 그 replica 를 8.4 로 major version upgrade | ☁️Azure | (Step 5 대체) |
| 3 | replica promotion → standalone GREEN 8.4 | ☁️Azure | (Step 9 대체) |
| 4 | GREEN HA = ZoneRedundant 구성 | ☁️Azure | (Step 5 대체) |
| 5 | promotion GTID 확보 → Data-in Replication 구성 | 💻VM → 🟩GREEN | Step 13-14 (+ Step 11-12 대체) |
| 6 | GREEN Read Replica 2대 구성 | 💻VM → ☁️Azure | Step 16 |

---

## 4. 전제 / 사전 점검

본 경로에서도 README 의 다음은 **그대로 선행** 합니다.

- **Step 1-3** — BLUE 호환성 검사(Upgrade Checker) / 파라미터 / DEFINER 점검. major version upgrade 전에 8.4 차단 요소를 반드시 제거 (upgrade 가 이 검증을 대신하지 않음)
- **Step 4** — BLUE 에 `syncuser` (`REPLICATION SLAVE`) 생성. promotion 후 Data-in Replication 에 그대로 사용
- **Step 13** — BLUE TLS root CA bundle (`/tmp/azure_mysql_ca_bundle.pem`) 준비

> ⚠️ `lower_case_table_names`, charset/collation, `time_zone`, `sql_mode` 등은 Read Replica 가 BLUE 를 그대로 이어받으므로 dump/load 경로의 "BLUE 와 동일하게 생성" 고민이 줄어듭니다. 단 **major version upgrade 후 8.4 에서 기본값이 바뀌는 항목** (예: `authentication_policy`, `caching_sha2_password` 관련) 은 Step 6 기준으로 재확인하세요.

---

## 5. 절차

### 5.1 BLUE 에 시딩용 Read Replica 추가

🟦 [BLUE] 기존 운영 Read Replica 2대에 더해 **시딩 전용 1대** 를 추가합니다 (운영 replica 를 직접 쓰지 않음 — 업그레이드/promotion 으로 소모됨).

```bash
az mysql flexible-server replica create \
  --resource-group <resource-group> \
  --replica-name <green-seed-name> \
  --source-server <blue-name> \
  --location <same-or-paired-region>

# 초기 sync 완료 및 lag 확인
az mysql flexible-server replica list -g <resource-group> -n <blue-name> -o table
```

> 복제본이 BLUE 를 충분히 따라잡아 lag 가 안정된 뒤 다음 단계로 진행하세요.

### 5.2 시딩용 replica 를 8.4 로 major version upgrade

☁️ [Azure] 추가한 복제본을 **8.4 로 in-place major version upgrade** 합니다.

```bash
az mysql flexible-server upgrade \
  --resource-group <resource-group> \
  --name <green-seed-name> \
  --version 8
# (--version 은 major 만 지정; CLI/포털에서 8.4 타깃으로 업그레이드)
```

> ⚠️ major version upgrade 는 되돌릴 수 없습니다. Step 1 Upgrade Checker 의 Error 항목을 모두 해소한 뒤 진행하세요.
> ⚠️ 업그레이드 대상이 **운영 replica 가 아닌 시딩 전용 replica** 인지 다시 확인하세요.

### 5.3 promotion (standalone GREEN 8.4)

☁️ [Azure] 업그레이드된 복제본을 **독립 서버로 promote** 합니다. promote 하면 BLUE→replica 복제가 끊기고 standalone primary 가 됩니다 — 이 서버가 곧 **GREEN** 입니다.

```bash
az mysql flexible-server replica stop-replication \
  --resource-group <resource-group> \
  --name <green-seed-name> \
  --yes
```

> promote 직후의 `@@GLOBAL.gtid_executed` 가 **"BLUE 의 어디까지 적용됐는지" 를 나타내는 기준 GTID** 입니다 (5.5 에서 사용). 이 값 덕분에 dump/load 경로의 `gtid reset` (Step 11-12) 이 **불필요** 합니다.

### 5.4 GREEN HA 구성

☁️ [Azure] promote 된 GREEN 에 HA(ZoneRedundant)를 구성합니다.

```bash
az mysql flexible-server update \
  --resource-group <resource-group> \
  --name <green-name> \
  --high-availability ZoneRedundant
```

> Read Replica 와 마찬가지로, HA 구성이 끝나고 서버가 안정된 뒤 다음 단계로 진행합니다.
> (Geo-redundant backup 은 dump/load 경로의 `gtid reset` 제약과 무관해졌지만, 운영 정책에 맞춰 설정)

### 5.5 promotion GTID 확보 → Data-in Replication 구성

promote 시점에 GREEN 이 이미 BLUE 의 GTID 집합을 `gtid_executed` 로 보유하므로, **GTID reset 없이** auto-position 으로 그 다음 트랜잭션부터 이어받습니다.

🟩 [GREEN] 기준 GTID 확인:

```sql
SELECT @@GLOBAL.gtid_executed AS green_gtid_at_promotion;
-- 이 값이 BLUE 의 promotion 시점까지의 좌표. 이후 replication 은 그 다음 GTID 부터.
```

🟩 [GREEN] Data-in Replication 시작 (README **Step 14 와 동일**, `gtid reset` 만 생략):

```bash
mysqlsh --uri <admin-user>@<green-fqdn>:3306 \
  --ssl-mode=REQUIRED --password='<password>' --sql <<EOF
SET @cert = '$(cat /tmp/azure_mysql_ca_bundle.pem)';

CALL mysql.az_replication_change_master_with_gtid(
  '<blue-fqdn>',
  'syncuser',
  '<password>',
  3306,
  @cert
);

CALL mysql.az_replication_start;

SHOW REPLICA STATUS\G
EOF
```

검증은 README **Step 15** 와 동일 (`Replica_IO_Running=Yes`, `Replica_SQL_Running=Yes`, `Seconds_Behind_Source=0`, `Auto_Position=1`, BLUE/GREEN `gtid_executed` 일치).

> ⚠️ `gtid reset` 을 하지 않는 이유: dump/load 경로는 GREEN 이 BLUE GTID 를 모른 채 새로 적재되므로 reset 으로 좌표를 주입해야 하지만, 본 경로의 GREEN 은 **복제본 출신이라 BLUE UUID 의 GTID 를 이미 `gtid_executed` 에 보유** 합니다. 여기에 reset 을 걸면 오히려 좌표가 깨질 수 있으니 **실행하지 마세요.**

### 5.6 GREEN Read Replica 2대 구성

README **Step 16** 그대로. promotion 으로 끊긴 시딩 replica 외에, GREEN 의 신규 Read Replica 2대를 만듭니다.

```bash
az mysql flexible-server replica create \
  --resource-group <resource-group> \
  --replica-name <green-replica-1> \
  --source-server <green-name> \
  --location <same-or-paired-region>

az mysql flexible-server replica create \
  --resource-group <resource-group> \
  --replica-name <green-replica-2> \
  --source-server <green-name> \
  --location <same-or-paired-region>
```

이후 **Step 17 (정합성 검증) → Step 18-20 (cutover)** 은 README 를 그대로 따릅니다.

---

## 6. 주의사항

- **major version upgrade 는 비가역** — Step 1 Upgrade Checker Error 해소가 선행되어야 함. 시딩 전용 replica 에서 수행하므로 운영 BLUE / 운영 replica 에는 영향 없음.
- **promote = 복제 단절** — promote 후에는 그 서버가 BLUE 변경을 자동으로 받지 않습니다. 5.5 의 Data-in Replication 을 걸어야 promotion 이후 BLUE 변경분이 다시 따라붙습니다. promote 와 change master 사이의 시간 동안 BLUE 변경은 auto-position 으로 메워집니다.
- **`gtid reset` 금지** — 5.5 의 ⚠️ 참고. 본 경로에서는 GTID reset 을 수행하지 않습니다.
- **Entra / DEFINER / 파라미터** — README 의 [Microsoft Entra authentication 사용 시 주의](../README.md), [docs/definer_handling.md](definer_handling.md), [docs/parameter_compatibility.md](parameter_compatibility.md) 는 본 경로에도 동일하게 적용됩니다.

---

## 참고 링크

- [MS Docs: Read replicas](https://learn.microsoft.com/en-us/azure/mysql/flexible-server/concepts-read-replicas)
- [MS Docs: Major version upgrade](https://learn.microsoft.com/en-us/azure/mysql/flexible-server/how-to-upgrade)
- [MS Docs: Configure Data-in Replication](https://learn.microsoft.com/en-us/azure/mysql/flexible-server/how-to-data-in-replication?tabs=bash%2Ccommand-line)
