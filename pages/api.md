## Overview

The registry answers a few public reads at `https://packages.nabi-lang.org/api/v1/`: a package's versions and who published them, a version's README, source archive and docs, and every package's docs state. They need no token. Writes (`nabi publish`, `nabi yank`, owners, trusted publishers) take a token and are made with `nabi`; they are not described here.

```sh
curl https://packages.nabi-lang.org/api/v1/packages/json
curl -H 'Accept: application/json' https://packages.nabi-lang.org/api/v1/packages/json
```

## Formats

Answers are NABION (`application/nabion`), the format of `nabi.nabion`, unless JSON is asked for:

- `Accept: application/json`, or any `Accept` that ranks `application/json` above `application/nabion`;
- or `?format=json` on the address (`?format=nabion` asks for NABION whatever `Accept` says).

Any other `format` is a 400. In JSON a struct is an object (its name dropped), `none` is `null`, a tuple is an array, and a variant is its path as a string, or an object of one member, the path, holding its data (`Dep::path("../x")` is `{"Dep::path": "../x"}`). Each answer carries `Vary: Accept`.

Every public read carries `Access-Control-Allow-Origin: *`, so a page on any site can read it with `fetch`. They are simple requests: send no headers but `Accept`, or the browser asks first with an `OPTIONS` request, which the API refuses (405).

## Package

`GET /api/v1/packages/<name>`

The package and every version in the index, oldest first.

| Field | Meaning |
|-------|---------|
| `name`, `native` | The name as asked for; `false` (`true` under `/api/v1/native/<name>`, a native package) |
| `owners` | Accounts that may publish it: `{ id, login }`, GitHub's numeric id and login |
| `orgs` | Organisations and teams shown as owners: `{ id, login }` |
| `versions` | Each `Version`, below |
| `official` | Its latest version is official: published from the nabi-lang organization |
| `downloads`, `recent_downloads` | Downloads of every version's archive: all, and in the last 90 days |

Each `Version`:

| Field | Meaning |
|-------|---------|
| `version` | Semver |
| `yanked`, `yank_message` | Yanked (new resolutions skip it), and why (`none` when not given) |
| `removed` | Why the registry took it down; `none` when it did not |
| `deps` | Dependencies, as the index line has them |
| `meta` | What it was published with: `description`, `license`, `keywords`, `categories`, `repository`, .. (only the fields given) |
| `has_readme` | A README was sent with it (see README) |
| `archive` | `{ sha256, size, url }` of its source archive; `none` when the registry keeps none |
| `downloads`, `recent_downloads` | Downloads of its archive: all, and in the last 90 days (UTC days, today included) |
| `published_by`, `yanked_by`, `unyanked_by` | `{ id, login, at }`: the GitHub account and the unix time; for trusted publishing the repository's owner, with `via { repository, workflow, ref, run_id, run_attempt, owner_id }`; `none` when not recorded |
| `official` | Published from the nabi-lang organization |

`GET /api/v1/native/<name>` is the same for a native package (a C library the index describes); it has no archives, and its downloads are 0.

## README

`GET /api/v1/packages/<name>/<version>/readme`

The README sent with that version, as `text/markdown`; in JSON, `{ "name", "version", "readme" }`. A 404 when the version was published without one. Also under `/api/v1/native/`.

## Download

`GET /api/v1/packages/<name>/<version>/download`

The version's source archive (`application/gzip`; every path under `<name>-<version>/`), as kept at publish. Check it against the version's `archive.sha256`, which the index line carries too. Its format does not change with `Accept`. Each `GET` answered with the whole archive counts one download; a `HEAD`, a `304` or an error does not.

## Docs

`GET /api/v1/packages/<name>/<version>/docs`

The docs the registry made of that version when it was published: `PackageDocs { name, version, status, api }`. `status` is `{ state, message }`, `state` being `ok`, `nolib` (no library, so no docs) or `failed` (`message` says why); `api` is the public modules as `nabi doc` lays them out. A 404 when none were made yet. [docs.nabi-lang.org](https://docs.nabi-lang.org/packages) renders them.

`GET /api/v1/docs`

Every package (taken-down ones left out), as a list of `{ name, description, deps, official, versions }`: `deps` names the latest version's normal dependencies, and each version is `{ version, yanked, repository, rev, docs }`, `docs` being its docs' `state`, or `""` when none were made.

## Deleting a version

`DELETE /api/v1/packages/<name>/<version>`

The one write described here, since `nabi` has no command for it: an owner deletes a version for 72 hours after its publish, while no version of another package depends on the package. It takes an account's token with the `yank` scope (`Authorization: Bearer pkg_..`), and answers `Deleted { name, version }`.

```sh
curl -X DELETE -H "Authorization: Bearer $TOKEN" https://packages.nabi-lang.org/api/v1/packages/json/0.3.1
```

The version's line leaves the index, its archive, README and docs leave the registry, and its number is never published again. Past 72 hours, or once another package depends on it, the answer is a `409` saying so: yank it with `nabi yank <name>@<version>` instead. The package's owners get a notice by mail. The account page lists the versions that may still be deleted, with a Delete button that asks once more.

## Badges

`GET /packages/<name>/badge.svg`

An SVG badge of the latest version for a README, with its Markdown on the package's page:

```md
[![json on packages.nabi-lang.org](https://packages.nabi-lang.org/packages/json/badge.svg)](https://packages.nabi-lang.org/packages/json)
```

## Caching

An answer that may be cached (READMEs a minute, docs an hour, archives a day) carries an `ETag`; send it back in `If-None-Match` for a `304` with no body. Package info and the docs list are never cached (`no-store`).

## Rate limits

Each address may make 300 reads a minute of `/api/v1/` (and of searches and missing package pages on the site). Past that the answer is a `429` with `Retry-After: 60`: wait that many seconds. `GET /api/health` is not limited.

## Errors

An error is a status and `Error { message: ".." }` (`{"message": ".."}` in JSON) saying what to do instead.

| Status | When |
|--------|------|
| 400 | A bad `format` |
| 401, 403 | A delete without a token, or with one that may not delete this package |
| 404 | No such package, version, README, archive or docs, or no such route |
| 405 | A method other than `GET` or `HEAD` (or `DELETE` of a version) |
| 409 | A delete past 72 hours, or of a version another package depends on: yank it instead |
| 429 | Over the rate limit; wait `Retry-After` seconds |
| 451 | The registry took the package or version down; `message` says why |
| 500, 503 | The registry failed; try again later |

## Health

`GET /api/health`

`ok`, the toolchain the site names and the package count, one `key value` a line, or a `503` and `failing` while the package list cannot be read. In JSON, `{ "status", "nabi", "packages" }`.
