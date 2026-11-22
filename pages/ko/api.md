## 개요

레지스트리는 `https://packages.nabi-lang.org/api/v1/`에서 몇 가지 공개 읽기에 답합니다. 패키지의 버전과 각 버전을 공개한 사람, 버전의 README, 소스 보관본, 문서, 그리고 모든 패키지의 문서 상태입니다. 토큰은 필요 없습니다. 쓰기(`nabi publish`, `nabi yank`, 소유자, 신뢰할 수 있는 게시자)는 토큰이 필요하며 `nabi`로 합니다. 여기서는 다루지 않습니다.

```sh
curl https://packages.nabi-lang.org/api/v1/packages/json
curl -H 'Accept: application/json' https://packages.nabi-lang.org/api/v1/packages/json
```

## 형식

JSON을 요청하지 않으면 답은 `nabi.nabion`의 형식인 NABION(`application/nabion`)입니다. JSON을 받으려면 다음 가운데 하나를 씁니다.

- `Accept: application/json`, 또는 `application/json`을 `application/nabion`보다 높게 매긴 `Accept`
- 주소에 `?format=json` (`?format=nabion`은 `Accept`와 상관없이 NABION을 요청합니다)

그 밖의 `format`은 400입니다. JSON에서 구조체는 객체(이름은 빠집니다), `none`은 `null`, 튜플은 배열이고, variant는 그 경로를 담은 문자열이거나, 데이터가 있으면 경로 하나를 키로 둔 객체입니다(`Dep::path("../x")`는 `{"Dep::path": "../x"}`). 모든 답에는 `Vary: Accept`가 붙습니다.

모든 공개 읽기에는 `Access-Control-Allow-Origin: *`가 붙어, 어느 사이트의 페이지든 `fetch`로 읽을 수 있습니다. 단순 요청이므로 `Accept` 말고는 헤더를 보내지 마십시오. 그러지 않으면 브라우저가 먼저 `OPTIONS` 요청을 보내고, API는 이를 거절합니다(405).

## 패키지

`GET /api/v1/packages/<name>`

패키지와 index에 있는 모든 버전입니다. 오래된 버전부터 나옵니다.

| 필드 | 뜻 |
|------|----|
| `name`, `native` | 요청한 이름, `false` (`/api/v1/native/<name>` 아래의 네이티브 패키지는 `true`) |
| `owners` | 공개할 수 있는 계정: `{ id, login }`, GitHub의 숫자 id와 로그인 |
| `orgs` | 소유자로 보이는 조직과 팀: `{ id, login }` |
| `versions` | 아래의 `Version` 목록 |
| `official` | 최신 버전이 공식인지: nabi-lang 조직에서 공개했는지 |
| `downloads`, `recent_downloads` | 모든 버전 보관본의 내려받기 수: 전체, 최근 90일 |

각 `Version`:

| 필드 | 뜻 |
|------|----|
| `version` | Semver |
| `yanked`, `yank_message` | 철회되었는지(새 의존성 해소는 건너뜁니다)와 그 이유 (밝히지 않았으면 `none`) |
| `removed` | 레지스트리가 게시를 중단한 이유. 중단하지 않았으면 `none` |
| `deps` | index 줄에 있는 그대로의 의존성 |
| `meta` | 공개할 때 함께 보낸 것: `description`, `license`, `keywords`, `categories`, `repository` 등 (보낸 필드만) |
| `has_readme` | README를 함께 보냈는지 (README 참고) |
| `archive` | 소스 보관본의 `{ sha256, size, url }`. 레지스트리가 두지 않았으면 `none` |
| `downloads`, `recent_downloads` | 보관본 내려받기 수: 전체, 최근 90일 (UTC 기준 날, 오늘 포함) |
| `published_by`, `yanked_by`, `unyanked_by` | `{ id, login, at }`: GitHub 계정과 unix 시각. 신뢰할 수 있는 게시는 저장소 소유자이며 `via { repository, workflow, ref, run_id, run_attempt, owner_id }`가 붙습니다. 기록이 없으면 `none` |
| `official` | nabi-lang 조직에서 공개했는지 |

`GET /api/v1/native/<name>`은 네이티브 패키지(index가 설명하는 C 라이브러리)에 대해 같은 답을 줍니다. 보관본은 없고, 내려받기 수는 0입니다.

## README

`GET /api/v1/packages/<name>/<version>/readme`

그 버전과 함께 보낸 README를 `text/markdown`으로 줍니다. JSON에서는 `{ "name", "version", "readme" }`입니다. README 없이 공개한 버전이면 404입니다. `/api/v1/native/` 아래에도 있습니다.

## 내려받기

`GET /api/v1/packages/<name>/<version>/download`

공개할 때 보관한 그 버전의 소스 보관본입니다(`application/gzip`, 모든 경로가 `<name>-<version>/` 아래에 있습니다). index 줄에도 있는 버전의 `archive.sha256`과 맞는지 확인하십시오. 형식은 `Accept`에 따라 바뀌지 않습니다. 보관본 전체로 답한 `GET` 하나가 내려받기 한 번으로 셉니다. `HEAD`, `304`, 에러는 세지 않습니다.

## 문서

`GET /api/v1/packages/<name>/<version>/docs`

레지스트리가 그 버전을 공개할 때 만든 문서입니다: `PackageDocs { name, version, status, api }`. `status`는 `{ state, message }`이고, `state`는 `ok`, `nolib`(라이브러리가 없어 문서도 없음), `failed`(`message`가 이유를 말합니다) 가운데 하나입니다. `api`는 `nabi doc`이 배치하는 대로의 공개 모듈입니다. 아직 만든 문서가 없으면 404입니다. [docs.nabi-lang.org](https://docs.nabi-lang.org/ko/packages)가 이것을 보여 줍니다.

`GET /api/v1/docs`

모든 패키지(게시 중단된 것은 빠집니다)를 `{ name, description, deps, official, versions }` 목록으로 줍니다. `deps`는 최신 버전의 일반 의존성 이름이고, 각 버전은 `{ version, yanked, repository, rev, docs }`이며, `docs`는 그 문서의 `state`이고 만든 문서가 없으면 `""`입니다.

## 버전 삭제

`DELETE /api/v1/packages/<name>/<version>`

`nabi`에 명령이 없어 여기서 다루는 유일한 쓰기입니다. 소유자는 버전을 공개하고 72시간 동안, 다른 패키지의 어떤 버전도 그 패키지에 의존하지 않는 한 버전을 삭제할 수 있습니다. `yank` 권한이 있는 계정 토큰(`Authorization: Bearer pkg_..`)이 필요하며, 답은 `Deleted { name, version }`입니다.

```sh
curl -X DELETE -H "Authorization: Bearer $TOKEN" https://packages.nabi-lang.org/api/v1/packages/json/0.3.1
```

그 버전의 줄은 index에서 빠지고, 보관본, README, 문서는 레지스트리에서 지워지며, 그 버전 번호는 다시 공개할 수 없습니다. 72시간이 지났거나 다른 패키지가 의존하면 답은 그 이유를 말하는 `409`입니다. 그때는 `nabi yank <name>@<version>`으로 철회하십시오. 패키지 소유자에게는 메일 알림이 갑니다. 계정 페이지에는 아직 삭제할 수 있는 버전이 나오고, 삭제 버튼은 한 번 더 묻습니다.

## 배지

`GET /packages/<name>/badge.svg`

README에 넣을 최신 버전의 SVG 배지입니다. 패키지 페이지에 Markdown이 함께 있습니다.

```md
[![json on packages.nabi-lang.org](https://packages.nabi-lang.org/packages/json/badge.svg)](https://packages.nabi-lang.org/packages/json)
```

## 캐시

캐시해도 되는 답(README 1분, 문서 1시간, 보관본 하루)에는 `ETag`가 붙습니다. `If-None-Match`로 돌려보내면 본문 없는 `304`를 받습니다. 패키지 정보와 문서 목록은 캐시하지 않습니다(`no-store`).

## 요청 제한

주소마다 1분에 `/api/v1/` 읽기(사이트의 검색과 없는 패키지 페이지 포함)를 300번까지 할 수 있습니다. 넘으면 답은 `Retry-After: 60`이 붙은 `429`이니, 그 초만큼 기다리십시오. `GET /api/health`는 제한하지 않습니다.

## 에러

에러는 상태 코드와, 대신 무엇을 하면 되는지 말하는 `Error { message: ".." }`(JSON에서는 `{"message": ".."}`)입니다. 메시지는 영어입니다.

| 상태 | 언제 |
|------|------|
| 400 | 잘못된 `format` |
| 401, 403 | 토큰 없이, 또는 이 패키지를 삭제할 수 없는 토큰으로 삭제를 요청했을 때 |
| 404 | 그런 패키지, 버전, README, 보관본, 문서, 경로가 없을 때 |
| 405 | `GET`, `HEAD`(버전에는 `DELETE`) 말고 다른 메서드 |
| 409 | 72시간이 지났거나 다른 패키지가 의존하는 버전의 삭제: 대신 철회하십시오 |
| 429 | 요청 제한을 넘었을 때. `Retry-After`초만큼 기다리십시오 |
| 451 | 레지스트리가 패키지나 버전의 게시를 중단했을 때. `message`가 이유를 말합니다 |
| 500, 503 | 레지스트리가 실패했을 때. 나중에 다시 시도하십시오 |

## 상태 확인

`GET /api/health`

`ok`, 사이트가 밝히는 도구 모음, 패키지 수를 한 줄에 `key value` 하나씩 주거나, 패키지 목록을 읽을 수 없는 동안에는 `503`과 `failing`을 줍니다. JSON에서는 `{ "status", "nabi", "packages" }`입니다.
