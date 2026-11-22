## 概觀

登錄庫在 `https://packages.nabi-lang.org/api/v1/` 提供幾種公開的讀取：套件的版本及其發布者、某個版本的 README、原始碼壓縮檔與文件、所有套件的文件狀態，以及安全性公告。這些讀取不需要權杖。寫入操作（`nabi publish`、`nabi yank`、擁有者、受信任的發布者）需要權杖，透過 `nabi` 進行，本頁不加說明。

```sh
curl https://packages.nabi-lang.org/api/v1/packages/json
curl -H 'Accept: application/json' https://packages.nabi-lang.org/api/v1/packages/json
```

## 格式

除非要求 JSON，回應一律是 NABION（`application/nabion`），也就是 `nabi.nabion` 的格式。以下方式可以要求 JSON：

- `Accept: application/json`，或任何將 `application/json` 排在 `application/nabion` 之前的 `Accept`；
- 或在位址加上 `?format=json`（`?format=nabion` 不論 `Accept` 為何都要求 NABION）。

其他 `format` 值會回應 400。在 JSON 中，結構是物件（名稱省略），`none` 是 `null`，元組是陣列；變體是表示其路徑的字串，帶有資料時則是只有一個成員的物件，鍵為路徑、值為資料（`Dep::path("../x")` 即 `{"Dep::path": "../x"}`）。每個回應都帶有 `Vary: Accept`。

所有公開讀取都帶有 `Access-Control-Allow-Origin: *`，因此任何網站上的頁面都能用 `fetch` 讀取。它們屬於簡單請求：除了 `Accept` 之外不要傳送任何標頭，否則瀏覽器會先送出 `OPTIONS` 請求，而 API 會拒絕它（405）。

## 套件

`GET /api/v1/packages/<name>`

該套件及其在索引中的所有版本，由舊到新排列。

| 欄位 | 意義 |
|------|------|
| `name`, `native` | 請求時使用的名稱；`false`（在 `/api/v1/native/<name>` 下為 `true`，即原生套件） |
| `owners` | 可以發布該套件的帳戶：`{ id, login }`，即 GitHub 的數字 id 與登入名稱 |
| `orgs` | 顯示為擁有者的組織與團隊：`{ id, login }` |
| `versions` | 各個 `Version`，見下文 |
| `official` | 其最新版本是否為官方版本，也就是由 nabi-lang 組織發布 |
| `downloads`, `recent_downloads` | 所有版本壓縮檔的下載次數：總計，以及最近 90 天 |

每個 `Version`：

| 欄位 | 意義 |
|------|------|
| `version` | 語意化版本號 |
| `yanked`, `yank_message` | 是否已撤回（新的相依解析會略過它），以及原因（未說明時為 `none`） |
| `removed` | 登錄庫下架它的原因；未下架時為 `none` |
| `deps` | 相依套件，與索引行中的寫法相同 |
| `meta` | 發布時附帶的資訊：`description`、`license`、`keywords`、`categories`、`repository` 等（只含有提供的欄位） |
| `has_readme` | 是否隨版本傳送了 README（請見 README） |
| `archive` | 原始碼壓縮檔的 `{ sha256, size, url }`；登錄庫未保存時為 `none` |
| `downloads`, `recent_downloads` | 其壓縮檔的下載次數：總計，以及最近 90 天（以 UTC 日計算，含當天） |
| `published_by`, `yanked_by`, `unyanked_by` | `{ id, login, at }`：GitHub 帳戶與 unix 時間；受信任發布時為儲存庫擁有者，並附帶 `via { repository, workflow, ref, run_id, run_attempt, owner_id }`；未記錄時為 `none` |
| `official` | 是否由 nabi-lang 組織發布 |

`GET /api/v1/native/<name>` 對原生套件（由索引描述的 C 函式庫）回應相同的內容；原生套件沒有壓縮檔，下載次數為 0。

## README

`GET /api/v1/packages/<name>/<version>/readme`

隨該版本傳送的 README，型別為 `text/markdown`；在 JSON 中為 `{ "name", "version", "readme" }`。如果該版本發布時沒有 README，回應 404。`/api/v1/native/` 下也有此端點。

## 下載

`GET /api/v1/packages/<name>/<version>/download`

該版本的原始碼壓縮檔（`application/gzip`；所有路徑都在 `<name>-<version>/` 之下），即發布時保存的內容。請用該版本的 `archive.sha256` 驗證它，索引行中也有這個值。它的格式不隨 `Accept` 改變。每個回應完整壓縮檔的 `GET` 計為一次下載；`HEAD`、`304` 或錯誤不計。

## 文件

`GET /api/v1/packages/<name>/<version>/docs`

登錄庫在該版本發布時為其產生的文件：`PackageDocs { name, version, status, api }`。`status` 為 `{ state, message }`，`state` 是 `ok`、`nolib`（沒有函式庫，因此沒有文件）或 `failed`（`message` 說明原因）；`api` 是依 `nabi doc` 的版面排列的公開模組。尚未產生文件時回應 404。[docs.nabi-lang.org](https://docs.nabi-lang.org/zh-hant/packages) 負責呈現這些文件。

`GET /api/v1/docs`

所有套件（已下架的除外），格式為 `{ name, description, deps, official, versions }` 的串列：`deps` 列出最新版本的一般相依套件，每個版本為 `{ version, yanked, repository, rev, docs }`，`docs` 是其文件的 `state`，未產生文件時為 `""`。

## 安全性公告

`GET /api/v1/advisories`

所有已發布的[安全性公告](/zh-hant/advisories)，由新到舊排列，包含已撤銷的公告（設有 `withdrawn`）。在 JSON 中，每則公告是一筆 [OSV](https://ossf.github.io/osv-schema/) 記錄（schema 1.6.0），放在 `{"advisories": [..]}` 中；在 NABION 中為 `Advisories { advisories: [Advisory { .. }] }`，其中 OSV 的 `type` 寫作 `kind`。`?package=<name>` 只保留提及該套件的公告。

```sh
curl 'https://packages.nabi-lang.org/api/v1/advisories?format=json'
```

`GET /api/v1/advisories/<id>` 回應單則公告（例如 `NABI-2026-0001`），`GET /api/v1/packages/<name>/advisories` 回應某個套件的公告。一筆記錄：

| 欄位 | 意義 |
|------|------|
| `id` | `NABI-<year>-<number>` |
| `aliases` | 同一漏洞在其他地方的編號：`CVE-..`、`GHSA-..` |
| `summary`, `details` | 一行摘要；Markdown 內文 |
| `affected` | 每項為 `{ package: { ecosystem: "Nabi", name }, ranges, versions }`；範圍為 `{ type: "SEMVER", events }`，每個事件是 `introduced`（`"0"` 表示從第一個版本起）、`fixed`、`last_affected`、`limit` 之一 |
| `severity` | `{ type: "CVSS_V3", score: "CVSS:3.1/.." }`（或 `CVSS_V4`）；可以為空 |
| `references` | `{ type, url }`；第一項是本站上的公告頁面 |
| `credits` | `{ name, contact, type }` |
| `published`, `modified`, `withdrawn` | RFC 3339 時間，UTC；`withdrawn` 只出現在已撤銷的公告上 |

當某個範圍涵蓋一個版本（依 OSV 的規則計算：從每個 `introduced` 到下一個 `fixed`，或直到並包含 `last_affected`），或 `versions` 列出了它，且公告未被撤銷時，該版本即受影響。套件頁面與版本頁面會顯示影響它們的公告。

## 刪除版本

`DELETE /api/v1/packages/<name>/<version>`

這是本頁說明的唯一一種寫入操作，因為 `nabi` 沒有對應的指令：版本發布後 72 小時內，只要沒有其他套件的任何版本相依於該套件，擁有者就可以刪除該版本。它需要一個帶有 `yank` 權限範圍的帳戶權杖（`Authorization: Bearer pkg_..`），回應為 `Deleted { name, version }`。

```sh
curl -X DELETE -H "Authorization: Bearer $TOKEN" https://packages.nabi-lang.org/api/v1/packages/json/0.3.1
```

該版本的那一行會從索引中移除，其壓縮檔、README 與文件會從登錄庫中移除，它的版本號不會再被發布。超過 72 小時，或已有其他套件相依於它時，回應為說明原因的 `409`：此時請改用 `nabi yank <name>@<version>` 將它撤回。該套件的擁有者會收到電子郵件通知。帳戶頁面會列出仍可刪除的版本，並提供一個會再次確認的刪除按鈕。

## 徽章

`GET /packages/<name>/badge.svg`

顯示最新版本的 SVG 徽章，可放進 README，套件頁面上提供對應的 Markdown：

```md
[![json on packages.nabi-lang.org](https://packages.nabi-lang.org/packages/json/badge.svg)](https://packages.nabi-lang.org/packages/json)
```

## 快取

可快取的回應（README 一分鐘、文件一小時、壓縮檔一天）帶有 `ETag`；在 `If-None-Match` 中將它送回，即可得到沒有內文的 `304`。套件資訊、文件串列與安全性公告一律不快取（`no-store`）。

## 速率限制

每個位址每分鐘最多可對 `/api/v1/`（以及網站上的搜尋與不存在的套件頁面）進行 300 次讀取。超過後回應為帶有 `Retry-After: 60` 的 `429`：請等待相應的秒數。`GET /api/health` 不受限制。

## 錯誤

錯誤由狀態碼與 `Error { message: ".." }`（JSON 中為 `{"message": ".."}`）組成，訊息會說明應改為怎麼做。訊息為英文。

| 狀態碼 | 時機 |
|--------|------|
| 400 | `format` 無效 |
| 401, 403 | 沒有權杖就要求刪除，或所用權杖無權刪除該套件 |
| 404 | 沒有這樣的套件、版本、README、壓縮檔、文件或安全性公告，或沒有這樣的路由 |
| 405 | 使用了 `GET` 或 `HEAD`（對版本還有 `DELETE`）以外的方法 |
| 409 | 超過 72 小時後刪除，或刪除其他套件相依的版本：請改為撤回 |
| 429 | 超過速率限制；請等待 `Retry-After` 秒 |
| 451 | 登錄庫已下架該套件或版本；`message` 說明原因 |
| 500, 503 | 登錄庫發生錯誤；請稍後再試 |

## 健康檢查

`GET /api/health`

回應 `ok`、網站標示的工具鏈與套件數量，每行一個 `key value`；在無法讀取套件清單期間，回應 `503` 與 `failing`。JSON 中為 `{ "status", "nabi", "packages" }`。
