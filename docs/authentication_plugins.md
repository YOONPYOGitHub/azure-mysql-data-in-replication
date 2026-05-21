# 인증 플러그인 호환성 (MySQL 8.0 → 8.4)

> [README.md](../README.md) Step 6 / Step 7 의 상세 참조 문서.
> 8.0 의 `mysql_native_password` / `caching_sha2_password` 양립 환경을 8.4 로 옮길 때의 호환성과 전략을 정리합니다.

---

## 1. 8.0 → 8.4 변경 요약

| 항목 | 8.0 | 8.4 |
|---|---|---|
| 시스템 변수 | `default_authentication_plugin` | **제거됨** |
| 신규 변수 | — | **`authentication_policy`** (MFA factor 정책. plugin enable 수단 아님) |
| `mysql_native_password` plugin | built-in, ACTIVE | **deprecated, 기본 DISABLED** (MySQL 9.0 에서 제거 예정). 활성화하려면 서버 옵션 `--mysql-native-password=ON` (또는 동일 파라미터) 필요 |
| `caching_sha2_password` | 기본 권장 | 기본 권장 (변동 없음) |

---

## 2. 가장 중요한 한 가지 확인

GREEN 에서 반드시 다음 쿼리로 확인:

```sql
SELECT plugin_name, plugin_status, plugin_type, plugin_library
  FROM information_schema.plugins
 WHERE plugin_name = 'mysql_native_password';
```

| `plugin_status` | 의미 | 영향 |
|---|---|---|
| `ACTIVE` | native_password 인증 가능 | BLUE 의 native_password 계정 그대로 사용 가능 |
| `DISABLED` 또는 결과 없음 | 인증 불가 | BLUE 의 native_password 계정 로그인 실패 → 대응 필요 |

> ⚠️ `SHOW PLUGINS WHERE Name = 'mysql_native_password'` 는 8.4 에서 syntax error 발생 (`SHOW PLUGINS` 는 WHERE 미지원). 반드시 위 `information_schema.plugins` 쿼리를 사용.

---

## 3. `authentication_policy` 의 정확한 의미 (8.4 GREEN)

8.4 는 `default_authentication_plugin` 을 제거하고 `authentication_policy` 를 도입했습니다. 단 이 변수는 흔히 오해되는 것과 달리 **"여러 plugin 중 어느 것을 허용할지" 가 아니라, 계정의 MFA (multi-factor authentication) 각 factor 의 정책** 을 정의합니다. plugin 자체를 **enable / load 하는 수단이 아님** 에 주의하세요.

```sql
SHOW VARIABLES LIKE 'authentication_policy';
```

| 값 | 의미 |
|---|---|
| `*,,` (기본값) | factor 1 = 필수 + 기본 plugin (`caching_sha2_password`). factor 2/3 = optional |
| `caching_sha2_password,,` | factor 1 plugin 을 명시적으로 `caching_sha2_password` 로 고정 |
| `caching_sha2_password,mysql_native_password,` | factor 1 = `caching_sha2_password`, factor 2 plugin = `mysql_native_password` (해당 plugin 이 별도로 ENABLED 되어 있어야 함) |

> ⚠️ `authentication_policy` 에 `mysql_native_password` 를 넣어도 plugin 이 DISABLED 면 로드되지 않습니다. plugin 활성화는 별도 서버 옵션 (`--mysql-native-password=ON` 또는 동일 효과의 Azure 파라미터) 으로 수행해야 합니다.

본 마이그레이션 권장 순서:

1. `information_schema.plugins` 에서 `mysql_native_password` 의 `plugin_status` 를 확인
2. `ACTIVE` 면 그대로 사용
3. `DISABLED` 거나 결과가 없으면, Azure 측에 plugin 을 enable 할 수 있는 서버 파라미터가 노출되어 있는지 확인
4. 활성화가 불가능하면 BLUE 단계에서 (또는 cutover 전 GREEN 에서) 해당 계정을 `caching_sha2_password` 로 전환

`authentication_policy` 자체는 본 마이그레이션의 핵심 전환 수단이 **아닙니다**. 기본값 `*,,` 로 두어도 무방하며, MFA factor 를 추가로 운영할 때만 조정합니다.

---

## 4. 마이그레이션 전략 옵션

### A) Native 유지 (가장 단순)

| Step | 동작 |
|---|---|
| GREEN plugin | `mysql_native_password` = `ACTIVE` (DISABLED 면 Azure 측 plugin enable 파라미터로 활성화) |
| GREEN `authentication_policy` | 기본값 `*,,` 유지 (변경 불요) |
| dump/load | 계정 그대로 (`util.dumpInstance` 가 `CREATE USER ... IDENTIFIED WITH mysql_native_password BY ...` 생성) |
| 사후 | 없음 |

→ 본 가이드 기본 채택.

### B) Caching_sha2 로 사전 전환 (BLUE 에서)

| Step | 동작 |
|---|---|
| BLUE 에서 사전 작업 | `ALTER USER 'app_xxx'@'%' IDENTIFIED WITH caching_sha2_password BY '<password>';` |
| 앱 클라이언트 | TLS 필수 (caching_sha2 는 비-TLS 경로에서 RSA key exchange 필요) |
| GREEN | `authentication_policy` 기본값 `*,,` 그대로 |

→ 보안 강화 필요 시. 클라이언트 드라이버 호환성 사전 검증 필수.

### C) GREEN 에서 사후 전환

| Step | 동작 |
|---|---|
| cutover 직후 | GREEN 에서 `ALTER USER ... IDENTIFIED WITH caching_sha2_password BY '<new-password>';` |
| 단점 | 모든 앱 비밀번호 rotation 필요, 다운타임 발생 |

→ 권장하지 않음.

---

## 5. `util.dumpInstance --includeUsers` 동작

### 5.1 화이트리스트 모드

```bash
mysqlsh ... -- util dump-instance "/data/dump_blue" \
  --users=true \
  --includeUsers="<app-user-1>@%" \
  --includeUsers="<app-user-2>@%"
```

- `--includeUsers` 가 1개라도 있으면 **화이트리스트 모드** — 명시된 계정만 dump
- `--excludeUsers` 와 동시 사용 시 include 가 우선

> 💡 **형식 노트**: 위 예시 (`--includeUsers="user@%"`) 는 본 가이드 환경에서 검증된 형식입니다. MySQL Shell 공식 문서는 user account string 을 `'user_name'@'host_name'` 로 명시하길 권장하므로, 환경에 따라 `--includeUsers="'app_user_1'@'%'"` 형식을 쓰면 파싱 모호성을 줄일 수 있습니다. 단 한 명령 안에서 두 형식을 섞지는 마세요.

### 5.2 일반적으로 제외되는 계정 카테고리

MySQL Shell 공식 문서가 보장하는 동작은 다음 두 가지뿐입니다:

- `--users=true` + `--includeUsers=...` 로 **명시한 계정만** dump 에 포함됨
- `loadDump` 시 현재 사용자 자신의 statement 는 skip 됨 (`loadUsers=true` 의 기본값은 `false`)

그 외 "빌트인 / 관리자 계정 자동 제외" 는 **운영 환경마다 차이가 있을 수 있으므로 의존하지 마세요**. 일반적으로는 다음 카테고리는 includeUsers 에 명시하지 않으면 dump 에 들어가지 않습니다:

| 카테고리 | 계정 예시 | 비고 |
|---|---|---|
| MySQL 빌트인 | `mysql.sys`, `mysql.session`, `mysql.infoschema` | 모든 인스턴스에 동일하게 존재 |
| Azure PaaS 내부 | `azure_superuser@127.0.0.1`, `@localhost` | 환경 고유 — GREEN 도 자체 생성 |
| 서버 admin 계정 | `--admin-user` 로 지정한 관리자 (사용자가 생성한 관리자, Entra ID admin 등) | GREEN 에도 별도로 구성 |

> ⚠️ 위 표는 "보통 명시하지 않으면 dump 에 들어가지 않는 카테고리" 일 뿐입니다. **반드시 dump 완료 로그의 `M users will be dumped` 값이 `--includeUsers` 개수와 일치하는지 + load dry-run 결과로 관리자/내부 계정이 섞여 있지 않은지 확인** 하세요. admin 계정이 우연히 들어가도 GREEN 의 admin 비밀번호와 충돌해 load 실패 또는 권한 덮어쓰기로 이어질 수 있습니다.

### 5.3 검증

dump 완료 로그:
```
M users will be dumped.
```
→ `M` 이 `--includeUsers` 개수와 일치하는지 확인. 0 이 나오면 placeholder 를 그대로 적은 것 (예: `<app-user-1>@%` 를 실제 값으로 치환 안 함).

---

## 6. 트러블슈팅

| 증상 | 원인 | 해결 |
|---|---|---|
| `ERROR 1524 (HY000): Plugin 'mysql_native_password' is not loaded` | GREEN plugin DISABLED | Azure 측 plugin enable 파라미터 (`--mysql-native-password=ON` 또는 동일 효과) 로 활성화하거나, 계정을 caching_sha2 로 전환. `authentication_policy` 에 plugin 명을 추가하는 것은 plugin 활성화 효과가 없음 |
| `Authentication plugin 'caching_sha2_password' cannot be loaded` (클라이언트) | 구식 드라이버 | 드라이버 업그레이드 또는 TLS 강제 |
| dump 로그에 `0 users will be dumped` | placeholder 미치환 | `--includeUsers` 값을 실제 계정명으로 |
| `SHOW PLUGINS WHERE ...` 1064 syntax error | `SHOW PLUGINS` 는 WHERE 미지원 | `information_schema.plugins` 사용 |

---

## 7. 참고

- [MySQL 8.4: Pluggable Authentication](https://dev.mysql.com/doc/refman/8.4/en/pluggable-authentication.html)
- [MySQL 8.4: `authentication_policy`](https://dev.mysql.com/doc/refman/8.4/en/server-system-variables.html#sysvar_authentication_policy)
- [Azure MySQL Flexible Server: Microsoft Entra authentication (concepts)](https://learn.microsoft.com/en-us/azure/mysql/flexible-server/security-entra-authentication)
- [Azure MySQL Flexible Server: Set up Microsoft Entra authentication (how-to)](https://learn.microsoft.com/en-us/azure/mysql/flexible-server/security-how-to-entra)
