## 概述

注册表在 `https://packages.nabi-lang.org/api/v1/` 提供几种公开的读取：包的版本及其发布者，某个版本的 README、源代码压缩包和文档，所有包的文档状态，以及安全公告。它们不需要令牌。写入操作（`nabi publish`、`nabi yank`、所有者、可信发布者）需要令牌，通过 `nabi` 完成，本页不作介绍。

```sh
curl https://packages.nabi-lang.org/api/v1/packages/json
curl -H 'Accept: application/json' https://packages.nabi-lang.org/api/v1/packages/json
```

## 格式

除非请求 JSON，响应都是 NABION（`application/nabion`），即 `nabi.nabion` 的格式。以下方式可以请求 JSON：

- `Accept: application/json`，或任何把 `application/json` 排在 `application/nabion` 之前的 `Accept`；
- 或在地址上加 `?format=json`（`?format=nabion` 无论 `Accept` 是什么都请求 NABION）。

其他 `format` 值返回 400。在 JSON 中，结构体是对象（名称省略），`none` 是 `null`，元组是数组；变体是表示其路径的字符串，带数据时则是只有一个成员的对象，键为路径，值为数据（`Dep::path("../x")` 即 `{"Dep::path": "../x"}`）。每个响应都带有 `Vary: Accept`。

所有公开读取都带有 `Access-Control-Allow-Origin: *`，因此任何网站上的页面都可以用 `fetch` 读取。它们是简单请求：除 `Accept` 外不要发送任何请求头，否则浏览器会先发送 `OPTIONS` 请求，而 API 会拒绝它（405）。

## 包

`GET /api/v1/packages/<name>`

该包及其在索引中的所有版本，按从旧到新排列。

| 字段 | 含义 |
|------|------|
| `name`, `native` | 请求时使用的名称；`false`（在 `/api/v1/native/<name>` 下为 `true`，即原生包） |
| `owners` | 可以发布该包的账户：`{ id, login }`，即 GitHub 的数字 id 和登录名 |
| `orgs` | 显示为所有者的组织和团队：`{ id, login }` |
| `versions` | 各个 `Version`，见下文 |
| `official` | 其最新版本是否为官方版本，即由 nabi-lang 组织发布 |
| `downloads`, `recent_downloads` | 所有版本压缩包的下载量：总计，以及最近 90 天 |

每个 `Version`：

| 字段 | 含义 |
|------|------|
| `version` | 语义化版本号 |
| `yanked`, `yank_message` | 是否已撤回（新的依赖解析会跳过它），以及原因（未说明时为 `none`） |
| `removed` | 注册表下架它的原因；未下架时为 `none` |
| `deps` | 依赖，与索引行中的写法相同 |
| `meta` | 发布时附带的信息：`description`、`license`、`keywords`、`categories`、`repository` 等（只含提供了的字段） |
| `has_readme` | 是否随版本发送了 README（见 README） |
| `archive` | 源代码压缩包的 `{ sha256, size, url }`；注册表未保存时为 `none` |
| `downloads`, `recent_downloads` | 其压缩包的下载量：总计，以及最近 90 天（按 UTC 日计算，含当天） |
| `published_by`, `yanked_by`, `unyanked_by` | `{ id, login, at }`：GitHub 账户和 unix 时间；可信发布时为仓库所有者，并附带 `via { repository, workflow, ref, run_id, run_attempt, owner_id }`；未记录时为 `none` |
| `official` | 是否由 nabi-lang 组织发布 |

`GET /api/v1/native/<name>` 对原生包（由索引描述的 C 库）返回相同的内容；原生包没有压缩包，下载量为 0。

## README

`GET /api/v1/packages/<name>/<version>/readme`

随该版本发送的 README，类型为 `text/markdown`；JSON 中为 `{ "name", "version", "readme" }`。如果该版本发布时没有 README，返回 404。`/api/v1/native/` 下也有此接口。

## 下载

`GET /api/v1/packages/<name>/<version>/download`

该版本的源代码压缩包（`application/gzip`；所有路径都在 `<name>-<version>/` 下），即发布时保存的内容。请用该版本的 `archive.sha256` 校验它，索引行中也有这个值。它的格式不随 `Accept` 改变。每个返回完整压缩包的 `GET` 计为一次下载；`HEAD`、`304` 或错误不计。

## 文档

`GET /api/v1/packages/<name>/<version>/docs`

注册表在该版本发布时为其生成的文档：`PackageDocs { name, version, status, api }`。`status` 为 `{ state, message }`，`state` 是 `ok`、`nolib`（没有库，因此没有文档）或 `failed`（`message` 说明原因）；`api` 是按 `nabi doc` 的布局排列的公开模块。尚未生成文档时返回 404。[docs.nabi-lang.org](https://docs.nabi-lang.org/zh-hans/packages) 负责渲染这些文档。

`GET /api/v1/docs`

所有包（已下架的除外），形式为 `{ name, description, deps, official, versions }` 的列表：`deps` 列出最新版本的普通依赖，每个版本为 `{ version, yanked, repository, rev, docs }`，`docs` 是其文档的 `state`，未生成文档时为 `""`。

## 安全公告

`GET /api/v1/advisories`

所有已发布的[安全公告](/zh-hans/advisories)，按从新到旧排列，包括已撤销的公告（设有 `withdrawn`）。在 JSON 中，每条公告是一条 [OSV](https://ossf.github.io/osv-schema/) 记录（schema 1.6.0），放在 `{"advisories": [..]}` 中；在 NABION 中为 `Advisories { advisories: [Advisory { .. }] }`，其中 OSV 的 `type` 写作 `kind`。`?package=<name>` 只保留提到该包的公告。

```sh
curl 'https://packages.nabi-lang.org/api/v1/advisories?format=json'
```

`GET /api/v1/advisories/<id>` 返回单条公告（如 `NABI-2026-0001`），`GET /api/v1/packages/<name>/advisories` 返回某个包的公告。一条记录：

| 字段 | 含义 |
|------|------|
| `id` | `NABI-<year>-<number>` |
| `aliases` | 同一漏洞在其他地方的编号：`CVE-..`、`GHSA-..` |
| `summary`, `details` | 一行摘要；Markdown 正文 |
| `affected` | 每项为 `{ package: { ecosystem: "Nabi", name }, ranges, versions }`；区间为 `{ type: "SEMVER", events }`，每个事件是 `introduced`（`"0"` 表示从第一个版本起）、`fixed`、`last_affected`、`limit` 之一 |
| `severity` | `{ type: "CVSS_V3", score: "CVSS:3.1/.." }`（或 `CVSS_V4`）；可以为空 |
| `references` | `{ type, url }`；第一项是本站上的公告页面 |
| `credits` | `{ name, contact, type }` |
| `published`, `modified`, `withdrawn` | RFC 3339 时间，UTC；`withdrawn` 只出现在已撤销的公告上 |

当某个区间覆盖一个版本（按 OSV 的规则计算：从每个 `introduced` 到下一个 `fixed`，或直到并包括 `last_affected`），或 `versions` 列出了它，且公告未被撤销时，该版本即受影响。包页面和版本页面会显示影响它们的公告。

## 删除版本

`DELETE /api/v1/packages/<name>/<version>`

这是本页介绍的唯一一种写入操作，因为 `nabi` 没有对应的命令：版本发布后 72 小时内，只要没有其他包的任何版本依赖该包，所有者可以删除该版本。它需要一个带有 `yank` 权限范围的账户令牌（`Authorization: Bearer pkg_..`），响应为 `Deleted { name, version }`。

```sh
curl -X DELETE -H "Authorization: Bearer $TOKEN" https://packages.nabi-lang.org/api/v1/packages/json/0.3.1
```

该版本的那一行会从索引中移除，其压缩包、README 和文档会从注册表中移除，它的版本号不会再次发布。超过 72 小时，或已有其他包依赖它时，响应为说明原因的 `409`：此时请改用 `nabi yank <name>@<version>` 撤回它。该包的所有者会收到邮件通知。账户页面列出仍可删除的版本，并提供一个会再次确认的删除按钮。

## 徽章

`GET /packages/<name>/badge.svg`

显示最新版本的 SVG 徽章，可放进 README，包页面上提供了对应的 Markdown：

```md
[![json on packages.nabi-lang.org](https://packages.nabi-lang.org/packages/json/badge.svg)](https://packages.nabi-lang.org/packages/json)
```

## 缓存

可缓存的响应（README 一分钟，文档一小时，压缩包一天）带有 `ETag`；在 `If-None-Match` 中把它发回，即可得到没有响应体的 `304`。包信息、文档列表和安全公告从不缓存（`no-store`）。

## 速率限制

每个地址每分钟最多可对 `/api/v1/`（以及网站上的搜索和不存在的包页面）进行 300 次读取。超过后响应为带有 `Retry-After: 60` 的 `429`：请等待相应的秒数。`GET /api/health` 不受限制。

## 错误

错误由状态码和 `Error { message: ".." }`（JSON 中为 `{"message": ".."}`）组成，消息说明应改为怎样做。消息为英文。

| 状态码 | 何时 |
|--------|------|
| 400 | `format` 无效 |
| 401, 403 | 没有令牌就请求删除，或所用令牌无权删除该包 |
| 404 | 没有这样的包、版本、README、压缩包、文档或安全公告，或没有这样的路由 |
| 405 | 使用了 `GET` 或 `HEAD`（对版本还有 `DELETE`）以外的方法 |
| 409 | 超过 72 小时后删除，或删除其他包依赖的版本：请改为撤回 |
| 429 | 超过速率限制；请等待 `Retry-After` 秒 |
| 451 | 注册表已下架该包或版本；`message` 说明原因 |
| 500, 503 | 注册表出错；请稍后重试 |

## 健康检查

`GET /api/health`

返回 `ok`、网站声明的工具链和包的数量，每行一个 `key value`；在无法读取包列表期间，返回 `503` 和 `failing`。JSON 中为 `{ "status", "nabi", "packages" }`。
