# packages.nabi-lang.org

[![License: MIT OR Apache-2.0](https://img.shields.io/badge/license-MIT%20OR%20Apache--2.0-blue)](LICENSE-MIT)

*Clear rules, free as a butterfly.*

Source for https://packages.nabi-lang.org, the Nabi package registry: site and server. One program written in Nabi: it reads a checkout of the registry index ([packages-index](https://github.com/nabi-lang/packages-index)) and writes a static site to `public/`; `serve` serves that site plus GitHub login, publish tokens, trusted publishing from GitHub Actions, and the publish / yank API. The server is the only writer of the index: lines enter it through the publish API, never by pull request.

## Build

Needs the Nabi toolchain (`nabi`, `nabic`), `git`, SQLite 3 (`libsqlite3.so.0` on Linux: `apt install libsqlite3-0`; macOS has `/usr/lib/libsqlite3.dylib`), an index checkout, and the [web kit](https://github.com/nabi-lang/web) submodule at `web/` (clone with `git clone --recurse-submodules`, or run `git submodule update --init` in an existing clone). The default config assumes the repos sit side by side:

```
./
|-- nabi/                        # toolchain (github.com/nabi-lang/nabi)
|-- packages-index/                # registry index
`-- packages.nabi-lang.org/        # this repository
```

No toolchain? Install one (`curl -fsSL https://nabi.sh | sh`) or `cargo build --release` in `../nabi`.

```bash
nabi run                   # generate the site in public/ from the index in site.nabion
nabi run -- check          # generate; exit 1 on broken links or bad index lines
nabi run -- --demo         # generate from the sample index in fixtures/
nabi run -- --offline      # don't fetch READMEs with git (cache only)
nabi run -- --index <dir>  # use another index checkout
nabi run -- --data <dir>   # show metadata, publishers and owners from the server's data
nabi run -- serve          # serve public/ and the API (see Server)
nabi run -- backup <file>  # copy the server's database while it runs (see Data and backups)
nabi run -- export <file>  # the server's data as db.nabion has it (`-`: print)
nabi test                  # unit tests
tests/e2e.sh              # end-to-end test of serve
```

`fixtures/` holds a sample index (`--demo`) with more packages and edge cases than the real one, a sample `db.nabion` and `downloads.nabion` (`fixtures/data`), plus READMEs and source trees for some of them, for checking the site without git or network. Each package's latest commit is fetched into `.cache/git`: its README is rendered untrusted (HTML shown as text, non-http(s)/mailto links dropped), its tree is counted for the side panel (files, size, non-blank lines of `.nabi`). Each version's public items are its Docs tab (see Docs). Version dates are the commit dates of the index commits that added each version's line.

## Scripts

The page scripts are TypeScript and TSX: each file directly in `static/` is a page script, `static/ui/*.tsx` are the Preact components they render into the server's markup, and the kit's `web/js/*.ts` come along. `npm ci` (the same install brings `puppeteer-core` for `og/render.ts`), then `npm run build` bundles each page script to the `.js` beside it with esbuild (`web/tools/build.ts`: types erased, JSX for Preact, imports bundled, minified), and `npm run check` type-checks everything with `tsc`. Run the build before `nabi build`: the kit's scripts are built into the program and the site serves the rest. The `.js` files are build output and not checked in.

## Web kit

`web/` is [nabi-lang/web](https://github.com/nabi-lang/web), pinned to a commit. The site builds its `web` library in (`Dep::path("web/nabi")`): HTTP, the canonical-address rules, the shared header and footer markup, and the kit's files, which every build writes into `public/` at `/nabi.css`, `/theme.js`, `/keys.js`, `/copy.js`, `/logo.svg`, the icons and `/site.webmanifest`, plus the webfonts, copied from `web/assets/fonts` to `/fonts/` (served for a day with an ETag). The fonts are files, not built in, so the server's rebuilds need `web/assets/fonts` at run time; `og/render.ts` reads `web/css/nabi.css` and the mark through the templates. Move to a newer kit with:

```bash
git submodule update --remote web
nabi run -- check && nabi test
git commit -am "chore: bump the web kit"
```

## Preview

Serve over HTTP (the search index is loaded with `fetch`). Links are root-relative and canonical: no `.html`, a directory index is the directory, no trailing slash (`/packages/json` is `packages/json.html`, `/packages` is `packages/index.html`). `nabi run -- serve` resolves them and answers `.html`, `/index.html` and trailing-slash paths with a 301 to the canonical one (a bare `index` segment stays: it may name a docs page, `docs/index` of a module `index`); a plain file server only opens the pages themselves:

```bash
python3 -m http.server -d public 8000
```

## Languages

Every page is built in four languages (`web::lang::Lang`): English at its address, Korean under `/ko`, Simplified Chinese under `/zh-hans` and Traditional Chinese (as written in Taiwan) under `/zh-hant`, each with the same paths below it (`/ko/packages/json`, `/zh-hans/packages/json/versions`, `/zh-hant/categories`, `/zh-hans/publishing`, `/ko/api`, `/zh-hant/policy`, ..). `serve` answers every route in each language too: the search (`/zh-hans/packages?q=`), the 404s (a missing package or version, any page), login (`/zh-hant/login`, which comes back to `/zh-hant/me`), the account page and its forms (`/ko/me`, `/zh-hans/me/tokens`, `/zh-hant/logout`, .., which lead back under the same language), `/privacy` and `/terms` (to nabi-lang.org's page in that language), and the pages that say what went wrong. The header, the footer (`web::chrome::site_cols_for`, `legal_links_for`), the nav, buttons, labels and dates are in the page's language: Korean in 합니다체 as nabi-lang.org/ko writes, Chinese as the glossary of the docs repository (`i18n/glossary-zh.md`) has it (zh-Hans 包, 包注册表, 发布, 撤回; zh-Hant 套件, 套件登錄庫, 發布, 撤回, with Taiwan terms); a package's own text (its README, description, keywords, authors) stays as written, the README marked `lang="en"`. The guide, the API reference and the policy come from `pages/<dir>/publishing.md`, `api.md` and `policy.md` (`pages/ko/`, `pages/zh-hans/`, `pages/zh-hant/`). What stays English on the other pages: the API's own messages (an account form that the shared owners code refuses shows a title and sentence in the page's language, then the API's message), the mail notices, the advisory pages' own text and the descriptions in the header search's index.

The header has a language menu (`web::chrome::lang_menu_for`, its items from `chrome::menu_items`) that opens the same page in each other language, the search's query kept; nothing is remembered, it is a link. Each page names all four with `<link rel="alternate" hreflang>` (`en`, `ko`, `zh-Hans`, `zh-Hant`, and `x-default` the English) and carries its `og:locale`; `<html lang>` is the language's tag (`zh-Hans`, `zh-Hant`), which the kit's scripts and CSS read. The sitemap lists every language's pages, and `robots.txt` keeps each account page out (`/me`, `/ko/me`, `/zh-hans/me`, `/zh-hant/me`). The header also links the Nabi home (nabi-lang.org, `/ko` or `/zh-hans` from a page in that language). `layout::tr(lg, en, ko, hans, hant)`, `layout::lp` (a path in a language, `/zh-hant/packages`) and `layout::in_lang` (an output file under `zh-hant/`) are how a page picks its words and links; `server::lang_path` reads a request's language. `static/search.tsx` reads `<html lang>` for its text (`web/js/lang/lang.ts`) and sends results to `/<dir>/packages/<name>`.

## Search and browse

`/packages?q=` (served by `serve`, works without JS) and the header's search box (`static/search.tsx`, over `/search-index.json`) match alike: every term must be in the name, the description or a keyword; exact name first, then name prefix, name, keyword, the rest, official packages first among equals. When nothing matches, each term found nowhere is replaced by the nearest name, part of a name (split at `-` / `_`) or keyword within a few edits (1 for 3 to 4 characters, 2 up to 8, 3 beyond; `names::edits`, which counts a swap of two neighbours as one), and the page shows those results under "Showing results for ..": `?q=jsn` shows `json`, `?q=lnalg` shows `linalg`.

`/categories` and `/keywords` list every category and keyword the packages' latest versions name, with how many packages have each; `/categories/<slug>` and `/keywords/<slug>` list those packages, official first, then by name. The slug is the word in lowercase ASCII letters and digits, each run of anything else one `-` (`Linear Algebra` is `/keywords/linear-algebra`); a word with no letter or digit in ASCII has no page and its chip searches for it instead. The side panel's keyword and category chips link these pages; on an old version's page, whose words may have changed since, they search. They are in the sitemap like every page.

Each package has a badge at `/packages/<name>/badge.svg` for its README: a flat, shields-style `nabi | v<latest>` (blue; orange for a pre-release, grey and `yanked` when every version is), with a `<title>` and `aria-label` naming the package and version. It is written with the site, so it changes with each build, and is served like a page (`web::http::FRESH`: checked on every load, kept a day by the CDN). The side panel shows it with its Markdown to copy.

## Server

`nabi run -- serve` serves `public/` and the API over plain HTTP on `PACKAGES_ADDR` (TLS ends at a reverse proxy). Run it from this directory (reads `site.nabion` and `.env`). At start and after each index commit it rebuilds the site in the background. `GET /api/health` answers `ok`, `nabi <release>` (the toolchain the footer names) and `packages <count>`, one a line, or a 503 `failing` while the package list cannot be read (`{"status", "nabi", "packages"}` when JSON is asked for, as below).

Settings live in `.env` (copy `.env.example`; process env wins over the file):

| Variable | Meaning |
|----------|---------|
| `PACKAGES_URL` | Public base URL; OAuth callback is `{URL}/auth/github/callback` |
| `PACKAGES_ADDR` | Listen address (default `127.0.0.1:8080`) |
| `GITHUB_CLIENT_ID`, `GITHUB_CLIENT_SECRET` | The GitHub OAuth app |
| `PACKAGES_ADMINS` | Comma-separated numeric GitHub user ids (the `id` of `https://api.github.com/users/<login>`) that may create publish tokens, add trusted publishers, publish, yank and moderate. A login is refused: logins change hands, ids do not |
| `PACKAGES_OPEN_PUBLISHING` | `1` lets every account do what the admins do with their own packages; unset (default), other accounts only log in and their tokens authorize nothing |
| `PACKAGES_DATA` | Directory of `registry.sqlite3` (accounts, sessions, tokens, owners, each version's metadata and publisher; see Data and backups), `downloads.nabion` (download counts), `audit.nabion` (the audit log), `readme/<name>/<version>.md` (READMEs sent with a publish), `docs/<name>/<version>/` (docs made at publish), `archives/` and `sources/` |
| `PACKAGES_SQLITE` | Optional path of the SQLite library to load; default `libsqlite3.so.0` (Linux), `/usr/lib/libsqlite3.dylib` (macOS) |
| `PACKAGES_INDEX` | Index checkout the server commits to and pushes from |
| `PACKAGES_TRUSTED` | Optional bootstrap file of trusted publishers (see Trusted publishing) |
| `PACKAGES_AUDIENCE` | The `aud` an OIDC token must carry (default: the host of `PACKAGES_URL`) |
| `PACKAGES_CLIENT_HEADER` | The header (`cf-connecting-ip`, `x-forwarded-for`) a trusted proxy puts the client's address in, for the rate limits; unset, the TCP peer is the client |
| `PACKAGES_RATE_LIMIT` | Changes (API writes, account forms) an account or token may make a minute (default 30); an address may make twice that |
| `PACKAGES_OFFICIAL_ORG` | GitHub's numeric id of the nabi-lang organization: versions its repositories publish through trusted publishing are official (see Official packages); unset, none are |
| `PACKAGES_REQUIRE_2FA` | `1` (default when unset): a login is refused unless GitHub says the account has two-factor authentication on, with a page saying how to turn it on; `0` lets any account log in (local development) |
| `PACKAGES_MAIL_FROM` | The address notices come from, optionally with a name (`Nabi packages <noreply@nabi-lang.org>`); a verified SES identity. Unset: mail is off and each notice is logged instead (see Notices by mail) |
| `PACKAGES_SES_REGION` | The SES region (`us-east-1`); unset: mail is off |
| `PACKAGES_IMG_KEY` | The secret (at least 32 characters, `openssl rand -hex 32`) README images are signed with for the image proxy (see README images); the site build reads it from the environment or `.env` too. Unset: READMEs link their images directly |
| `PACKAGES_IMG_CACHE_MB` | The image proxy's cache under `PACKAGES_DATA/img-cache`, in MiB at most (default 1024) |
| `GITHUB_API_TOKEN` | Optional GitHub token (no scopes) sent with the repository and owner lookups, for 5000 requests an hour in place of 60 per address |
| `GITHUB_OAUTH_URL`, `GITHUB_API_URL`, `GITHUB_OIDC_ISSUER` | Default GitHub; tests point them at a fake |
| `PACKAGES_SES_URL`, `AWS_EC2_METADATA_SERVICE_ENDPOINT` | Default `https://email.<region>.amazonaws.com` and `http://169.254.169.254`; tests point them at the fake |

Login is GitHub OAuth only (`read:user user:email`) and open to anyone: the header always offers it, and an account that may not act only logs in. It uses PKCE (S256): `/login` keeps a code verifier for its `state` in the server's memory for 10 minutes (at most 4096 logins at once) and sends GitHub only its challenge; the callback takes the verifier, once, and sends it with the code, so a stolen code is useless without it. A login cut short by a restart is started again. Unless `PACKAGES_REQUIRE_2FA=0`, the GitHub account must have two-factor authentication on: GitHub's `GET /user` reports `two_factor_authentication` to the user's own token, and a login without it (or where GitHub does not say) is refused before any account or session is stored, with the page linking GitHub's security settings and saying to log in again afterwards. The account keeps GitHub's id, login, display name and avatar address from the last login, and the primary verified email address from `GET /user/emails` (for notices; a login where GitHub does not answer keeps the one on record, and GitHub's noreply address counts as none); pages draw avatars from the id alone (`https://avatars.githubusercontent.com/u/<id>?s=<px>&v=4`). Pages are built logged out; for a request with a live session `serve` swaps the header's login button for an account menu (`<details>`, no script) and sends the page `no-store`. Sessions are a 32-byte cookie (`__Host-pkg_session`: this host only, https, every path) stored as SHA-256, at most 10 per account; a cookie that is not 64 hex digits is ignored before the database is read, and one that is reads three rows (its session, account and lock), not the whole data. Each session keeps when it logged in, when a request last came with it (written at most once an hour) and a short name of the browser (`Firefox on Linux`; the User-Agent itself is not kept). It ends after 7 days without a request and 30 days after its login at the latest. The account page lists the account's sessions with a Log out button on each and Log out everywhere (`POST /me/sessions/<id>/logout`, `POST /me/sessions/logout-all`); every form carries the session's CSRF token. Publish tokens (`pkg_` + 64 hex) are admin-only until `PACKAGES_OPEN_PUBLISHING` is set, stored as SHA-256 and compared in constant time. Each lasts the days chosen when it is made (90 by default, at most 365) and may be limited to some packages; a limited token moderates nothing, even an admin's. A token also has scopes, ticked on the account page: `publish-update` (new versions of a package that exists) and `yank` (yank and unyank), the defaults; `publish-new` (a package's first version); `owners` (the owners and trusted publishers routes, invitations included); and, for an admin, `admin`, without which an admin's token has no admin powers (moderation, other accounts' packages, reserved names, the new-name cap). A refused call names the scope it lacked and where to make a token with it. Tokens made before scopes may do everything but `admin`, and the account page says so. Trusted publishing tokens may publish (new or not) and yank their packages. The NABION API takes `Authorization: Bearer pkg_..`:

The public reads (`GET` and `HEAD` of `/api/v1/packages/..`, `/api/v1/native/..`, `/api/v1/docs` and `/api/v1/advisories..`) answer JSON for `?format=json` or an `Accept` that ranks `application/json` above `application/nabion` (`api::wants_json`), NABION otherwise; the NABION answer is parsed and written as JSON (`json::write`: a struct is an object without its name, `none` is `null`, a variant with data an object keyed by its path), a README is `{ name, version, readme }`, and an archive stays an archive. Any other `format` is a 400. They carry `Access-Control-Allow-Origin: *` and `Vary: Accept`, errors included; routes that take a token and writes carry neither. `/api` is their reference for users (`pages/api.md`); `/api/v1` redirects there. Keep it in step with the routes.

| Route | Purpose |
|-------|---------|
| `GET /api/v1/me` | account + publish flag |
| `POST /api/v1/publish` | `Publish { entry: Package { .. }, meta: { .. } }`: the index entry `nabi publish` prints and the package's metadata; answers `Published { name, version, file, warnings }`. A version already in the index from the same tree that was not published through the API (written by a maintainer with `nabi publish --index-dir`) gets the metadata and README it lacks instead of a 409 |
| `POST /api/v1/yank` | `Yank { name, version, undo, native, message }`; `message` (at most 512 bytes) is the reason, cleared by an unyank |
| `DELETE /api/v1/packages/<name>/<version>` | an owner's account token with the `yank` scope (not a trusted publishing one): deletes the version within 72 hours of its publish while no version of another package depends on the package (see Deleting a version); answers `Deleted { name, version }` |
| `GET /api/v1/packages/<name>` | no token: `owners` (accounts), `orgs` (organisations and teams on record), and each `Version { version, yanked, yank_message, deps, meta, has_readme, archive, downloads, recent_downloads, published_by, yanked_by, unyanked_by, official }`, then `official` (its latest version's) and the package's `downloads` and `recent_downloads` (every version's); each actor is `Actor { id, login, at }`, plus `via` for trusted publishing, where `id` and `login` are the repository owner's (the nabi-lang organization's for an official version), not the run's; `deps` is as in the index line |
| `GET /api/v1/packages/<name>/<version>/readme` | no token: the README sent with that version, `text/markdown`; 404 when none was sent |
| `GET /api/v1/packages/<name>/<version>/download` | no token: the source archive kept at publish (`application/gzip`, every path under `<name>-<version>/`); its SHA-256 and size are the version's `archive`. Counted as a download (see Downloads) |
| `GET /api/v1/native/<name>` | the same for a native package (and `/<version>/readme`) |
| `POST /api/v1/trusted-publishing/token` | no token: `TrustedPublishing { jwt: ".." }` (or `{"jwt": ".."}`), a GitHub Actions OIDC token; answers `TrustedToken { token, expires, packages }` |
| `GET /api/v1/trusted-publishers` | the trusted publishers of the packages the account owns (admins: all) |
| `POST /api/v1/trusted-publishers` | `TrustedPublisher { package, repository, workflow, environment }`; answers the record with its `id` and the owner's GitHub id |
| `POST /api/v1/trusted-publishers/remove` | `Remove { id }` |
| `POST /api/v1/owners` | `Owner { package, login }`: a user who has logged in here (answers `Invited { package, login }`; they own it once they accept), or an organisation or `org/team` (answers `Added { package, login, org }`) |
| `POST /api/v1/owners/accept` | `Owner { package }`: the token's account accepts its invitation |
| `POST /api/v1/owners/remove` | `Owner { package, login }`: an owner or an open invitation; the login is resolved to its GitHub id first |
| `GET /api/v1/admin` | admins: `Moderation { locked, removed, approved }` |
| `POST /api/v1/admin/lock` | admins: `Lock { id, reason, undo }`: a GitHub id may not log in; its sessions end, its tokens and the trusted publishes it starts are refused |
| `POST /api/v1/admin/takedown` | admins: `Takedown { name, version, native, reason, undo }`: every version it covers (all when `version` is `""`) is yanked, the site leaves the package out, and the API answers 451 with the reason. Undone, the versions stay yanked |
| `POST /api/v1/admin/approve` | admins: `Approve { name, undo }`: a reserved or look-alike name may be published |
| `GET /api/v1/advisories` | no token: the public advisories (see Security advisories); `?package=<name>`; `?state=draft` with a token: the drafts it may edit |
| `GET /api/v1/advisories/<id>` | no token: one; a draft only to its packages' owners and the admins |
| `GET /api/v1/packages/<name>/advisories` | no token: the public advisories on a package |
| `POST /api/v1/advisories` | an OSV record in JSON (or `Advisory { .. }`); an admin's (`admin` scope) is published at once, an owner's (`owners` scope, owning every package it names) is a draft. Answers 201 with the record and `Location` |
| `PUT /api/v1/advisories/<id>` | the record again: admins edit any, owners their drafts |
| `POST /api/v1/advisories/<id>/publish` | admins: publish a draft |
| `POST /api/v1/advisories/<id>/withdraw` | admins: `Withdraw { reason }` or `{"reason": ".."}` |

A package's owners (and the admins) manage its owners on the account page or through the API, like its trusted publishers; while publishing is closed only the admins do. A user is invited, and owns the package (publishes and yanks it) once they accept on their account page; invitations lapse after 30 days. An organisation or team is listed by an admin, or by an owner once one of the organisation's repositories is a trusted publisher of the package; it is shown on the package's page with the org's avatar but grants no account anything, since login asks GitHub for no membership: its members publish through trusted publishing. Every right is checked against GitHub's numeric ids, never logins. The package page also shows the owner of each trusted publisher's repository and of each trusted publish (`nabi-lang` for nabi-lang's packages), from the publisher's `owner_id` or the token's `repository_owner_id`.

An index line holds only what resolution needs, named as in the manifest: `name`, `version`, `deps`, `features`, `source`, `tree` (the commit's git tree hash), `yanked`, `toolchain`, `links`, and `official` (set by the server, below). A dependency is `{ name, req, kind, registry, optional, features, default_features, package, target }`: `package` is the package it names when `name` is a rename (as Cargo's), `target` limits it to a triple or a `cfg(..)` expression, which the client evaluates.

Index lines stay strict: a field the server does not know is refused, because every reader of the index must understand every line it resolves. The server is deployed before the clients that write a new field, so it learns the field first; a field older clients would misread also takes a higher `v` on the line.

`meta` is forward compatible instead. The known keys are the manifest's descriptive fields (`description`, `license`, `license_file`, `authors`, `homepage`, `documentation`, `repository`, `readme`, `keywords`, `categories`, `include`, `exclude`, `publish`, `metadata`, `links`, `default_run`), what the client measured (`has_lib`, `bin_names`, `size`: packed bytes) and `readme_content` (the README text, at most 512 KiB). They are checked; any other key is kept as sent (at most 32 keys, 16 KiB), returned in the API with the rest, and named in the reply's `warnings`, never refused. The metadata is kept in the database with the account and time of the publish, yank and unyank; the README text in its own file, shown on the package page in place of the commit's README.

### Notices by mail

The owners of a package get a short plain-text mail when a version is published (not for a version only filled in), yanked, unyanked or deleted, when an owner is invited, added (an organisation listed, an invitation accepted) or removed, when a trusted publisher is added or removed, and when a security advisory on it is published (its drafter too); an account gets one when a publish token is created on it. An invited or removed account gets that notice too. Each says who did it and when, links the package page, and says what to do if it was not the reader: revoke their tokens and log out unknown sessions at `/me`, then write to security@nabi-lang.org. Mail goes to the primary verified address GitHub gave at login; the account page shows it and has the settings: notices on or off, and each kind on its own (all on by default).

A change only queues its mails (at most 1000 waiting) and returns; one thread sends them, so a publish never waits on mail. An address gets at most 20 an hour; past that they are dropped and logged. The log names the account id, never the address. With `PACKAGES_MAIL_FROM` and `PACKAGES_SES_REGION` set, the thread sends through Amazon SES v2 (`POST /v2/email/outbound-emails`, `Simple` content with a `List-Unsubscribe` header pointing at the settings, which the body's footer links as well), signed with Signature Version 4 (`src/server/aws.nabi`, tested against AWS's example vectors) using the instance role's temporary credentials from IMDSv2 (a session token, then `iam/security-credentials/<role>`), kept until five minutes before they expire and fetched again when SES refuses them. No access keys are configured. The instance's role needs `ses:SendEmail` on the sending identity, and IMDSv2 must be reachable from the process (a container needs a hop limit of 2). Without the two settings mail is off: each notice is written to the log in full, which is what development and the tests use.

### Security advisories

The registry keeps advisories in the [OSV format](https://ossf.github.io/osv-schema/) (`src/osv.nabi`, routes in `src/server/advisories.nabi`), in the database's `advisories` table. Each has an id `NABI-<year>-<number>` given by the server (the year of its creation, numbered from `0001`), `aliases` (`CVE-..`, `GHSA-..`), a one-line `summary` (at most 200 bytes), Markdown `details` (at most 64 KiB, rendered untrusted), `affected` packages of this registry (ecosystem `Nabi`, each in the index) with `SEMVER` ranges (`introduced`, then `fixed`, `last_affected` or `limit`; `introduced: "0"` is every version from the first) or a list of `versions`, `severity` as a CVSS v3 or v4 vector (optional), `references` (https) and `credits`. A refused record is a 400 saying what to write. The server sets `published`, `modified` and `withdrawn` (RFC 3339, UTC) and adds the advisory's page as the first `ADVISORY` reference in the JSON.

An admin's token with the `admin` scope adds one (`POST`), published at once, edits one (`PUT`) in any state, and withdraws one (`POST ../withdraw`, with a reason): it stays listed, with `withdrawn` set, as OSV keeps withdrawn records, but no page shows it as affecting a version. An owner's token with the `owners` scope drafts one on packages the account owns, every one of them, and edits it while it is a draft; nobody else sees a draft (a 404) until an admin publishes it (`POST ../publish`). On publication the owners of each package it names, and its drafter, get a notice (kind `advisory`). Each step is in the audit log and in each named package's events (`advisory-draft`, `advisory-edit`, `advisory-publish`, `advisory-withdraw`), and a public change rebuilds the site.

The site lists them at `/advisories` (newest first, withdrawn ones marked) with a page each at `/advisories/<id>` (in the sitemap). A version that a published advisory affects has a red banner on its package and version pages (`N advisories affect <name> <version>`, each linked), an `advisory` tag in the Versions table, and the side panel's Advisories line lists the package's advisories, marking those that affect the version shown.

### Trusted publishing

A package's owners (or the admins) name GitHub Actions workflows that may publish it: repository `owner/repo`, workflow file, and optionally an environment, on the account page or through the API. While publishing is closed only the admins add them, and an OIDC token is granted only the packages whose publisher an admin added (an admin at the time of the exchange) or `PACKAGES_TRUSTED` gave. Adding one looks up the repository's owner id on GitHub, so a deleted and re-registered owner name does not match. A package with no owner on record (not published yet, or written by a maintainer with `nabi publish --index-dir`) gets its first trusted publisher only from an admin or from `PACKAGES_TRUSTED`: a NABION list read at each start, replacing the publishers it gave before, which the account page shows but cannot remove:

```nabion
[
    TrustedPublisher { package: "json", repository: "nabi-lang/json", owner_id: 12345678, workflow: "publish.yml" },
]
```

`owner_id` is GitHub's numeric id of the repository's owner (`12345678` above is a placeholder). The deploy writes the nabi-lang organization's from the infra variable `NABI_GITHUB_ORG_ID`; for another owner it is the `id` of `https://api.github.com/users/<owner>`.

The job sends its OIDC token to `POST /api/v1/trusted-publishing/token`. The server takes RS256 only, checks the signature against the issuer's JWKS (cached in `PACKAGES_DATA/jwks.json`, fetched again for an unknown `kid` at most once a minute), `iss`, `aud`, `exp` / `nbf` / `iat` with 60 s of leeway, and refuses a `jti` it has seen. The claims match a publisher when `repository` and `repository_owner_id` are its own, `workflow_ref` is its workflow file at any ref (the calling workflow, not a reusable one it calls), and `environment` is its environment when it names one. The answer is an `pkt_` token, stored as SHA-256, that lasts 30 minutes and may publish and yank only the matched packages; `nabi login` takes it (`/api/v1/me` says it may publish). Versions it publishes (and yanks it makes) record the user who triggered the run (`actor`, `actor_id`) as `published_by` with `via: Via { repository, workflow, ref, run_id, run_attempt, owner_id }`, shown as "by <repository owner> via GitHub Actions" with links to the repository and the run; their index commits are authored by the repository. `pages/publish.yml` is the workflow for a package's repository.

### Official packages

A version is official exactly when a trusted publisher in a repository of the nabi-lang organization publishes it: the OIDC token's `repository_owner_id` is `PACKAGES_OFFICIAL_ORG`. The server then appends `official: true` to its index line and records `official` with the release; a publish that sends `official` itself is refused. A package is official when its latest version is: the pages show an **Official** mark (a word, not a colour alone) on the package, in lists and in the header search, the home page lists them, `official:yes` (or `official:no`) in a search filters on it, and official packages come first among results that match equally well. To make another package official, move its repository into the organization and add the organization's workflow as its trusted publisher; its next version is official, earlier ones keep their line, and its owners stay.

A publish keeps the source: `git archive` of the published commit in `PACKAGES_DATA/archives/<key>/<version>.tar.gz` (at most 64 MiB), its SHA-256 in the version's record and written into the index line after `tree` (`archive`), served at `/download`. `nabi` downloads the archive and checks it against that line, so a version outlives its repository; it fetches the git source only for a version without `archive`.

### Downloads

Each `GET .../<version>/download` answered with the whole archive (a 200, not a HEAD, a 304 or an error) counts one download of that version on that day (UTC), in memory (`src/server/downloads.nabi`). Once a minute, when any changed, the counts are written whole to `PACKAGES_DATA/downloads.nabion` (`Count { name, version, day, n }`, `day` in days since 1970-01-01) in one rename, so a crash loses at most a minute of them; days before the last 90 are folded into one count per version (`day: 0`), so the file grows with the versions, not with time. A file that cannot be read at start is kept as `downloads.nabion.bad` and the counting starts over. The API answers the live counts: each version's `downloads` (all) and `recent_downloads` (the last 90 days, today included), and the package's sums. The pages show the counts of their last build (`--data` reads the file): the side panel every version's on a package page and the version's own on a version page, the Versions table a column; new downloads alone ask for a rebuild at most once an hour.

The side panel's Repository is always the source the commit was fetched from, never the manifest's `repository` (shown apart as "Stated repository" when it differs). It is marked **verified** when GitHub Actions in that very repository published the version (trusted publishing), and **not verified** otherwise: the fetch shows only that the commit is on a branch or tag there. README links carry `rel="nofollow ugc"`, and README images load lazily with no referrer.

### README images

With `PACKAGES_IMG_KEY` set, README images go through the registry, as GitHub's camo does for its READMEs: the build writes each http(s) `<img src>` as `/img/<mac>/<hex of the url>`, the mac being the first 16 bytes of the HMAC-SHA256 of the url with the key, so the server fetches only images its own pages link (`src/server/img.nabi`). A request with a mac that does not match is a 404. The server fetches the url with curl: http or https on the default port to a named host with no user name, resolved first and refused when any address is not on the public internet (`index::public_addrs`, the publish's SSRF guard), and pinned to those addresses (`resolve`), redirects followed by hand (at most 3, each checked again), within 10 s, at most 5 MiB (`max-filesize`, then the file's size), and kept only when the Content-Type is a png, jpeg, gif, webp, avif, svg, ico or bmp image. A refusal says why (403 an internal address, 413 too large, 415 not an image, 502 the host failed), as text, and the url is not tried again for 10 minutes. The request carries no cookie and no referrer, and the reader's never reach the image's host; the answer passes on no cookie either. An image is kept in `PACKAGES_DATA/img-cache/<sha256 of the url>` (its type beside it, `.type`) and served `public, max-age=31536000, immutable` (the address names the url), with `Content-Security-Policy: default-src 'none'; style-src 'unsafe-inline'; sandbox` and `nosniff`, so an svg never runs as a page of the site, and `Referrer-Policy: no-referrer`. Past `PACKAGES_IMG_CACHE_MB` the least recently served go (served since the start, else by when they were fetched). Each address may ask for 300 images a minute. With the key set the pages' CSP allows images only from the site and GitHub's avatars (`img-src 'self' data: https://avatars.githubusercontent.com`); without it, READMEs link their images directly and the CSP keeps `img-src 'self' data: https:`.

A publish checks the source before it takes any lock: the address must be https on a public host (no IP address, port, user name or `localhost`), and each source has a git cache of its own under `PACKAGES_DATA/sources/git/`, fetched over https only (`GIT_ALLOW_PROTOCOL`, which the process environment may widen for tests), without redirects, within 120 s, giving up below 1 KiB/s, and with each file it writes capped at about 256 MiB. The commit must be the tip of a branch or tag of that repository, or an ancestor of one: GitHub serves a fork's commits through the parent's address too, so a fetch alone proves nothing. Then `INDEX` covers the index write (reset to upstream, append or flip `yanked`, commit as the publishing account, push, each git step within 60 s; a failed push resets and answers 503), and `LOCK`, inside it, the database's read and write, in one transaction. Reads take no lock: each reads a snapshot of the database. Docs are made after both are released. Entry and metadata validation, the source checks and archives, and the commit flow are in `src/index.nabi`.

New names are checked too (`src/server/names.nabi`): at most 64 characters; not reserved (the toolchain's and the standard library's names, `nabi-*`, `std-*`, `core-*`); not an official package's name; not a look-alike of a protected name, that is one edit apart (both of four characters or more) or the same once case, `-` / `_`, `0` / `o`, `1` / `l` / `i`, `5` / `s`, `rn` / `m` and `vv` / `w` are folded (`names::skeleton`); and not the same as any name in the index once folded. Protected are the official names (the nabi-lang organization's packages, `names::FIRST_PARTY`, and every package with an official version), the toolchain's names (`names::TOOLCHAIN`; the other reserved words, `test` or `main`, only refuse their folded spellings, so `text` and `mail` are free), and the popular packages: those with `names::POPULAR` (1000) downloads or more, all versions, as the server counts them at the publish. One edit from any other package is a name of its own. An admin's approval lets a refused name through; an account takes at most 10 new names a day. Rate limits (`src/server/limit.nabi`) count in memory: logins 20 a minute per address, changes `PACKAGES_RATE_LIMIT` a minute per account or token and twice that per address, trusted publishing exchanges 20 a minute per address; past them the answer is a 429 with `Retry-After`. Moderation steps, logins and logouts, deleted versions, and changes to tokens, owners, invitations and trusted publishers are logged and appended to `PACKAGES_DATA/audit.nabion` (`Audit { at, by, action, target, reason }`, `by` a GitHub id). Each package also keeps its own log in `db.nabion` (`Event { package, at, by, who, action, detail }`, the newest 100 a package): publishes, yanks, unyanks and deletes (with the workflow run for a trusted publish), owner invitations, additions, declines and removals, trusted publishers added and removed, and tokens created and revoked (on the packages a token is limited to, else on every package its account owns). The account page shows the latest 30 of the packages the account owns, to their owners only.

### Deleting a version

An owner may delete a version for 72 hours after its publish (`delete::DELETE_SECS`, from the publish time on record; a version without one, written with `--index-dir`, is only yanked), while no version of another package depends on the package (`index::dependents`, any kind of dependency, renamed or not), on the account page (Recent versions: Delete, then a page that asks once more) or with `DELETE /api/v1/packages/<name>/<version>`. The token needs the `yank` scope, as yanking does: a delete is a yank that also takes the version back, and only in the first hours, when nothing has come to rely on it. A trusted publishing token does not delete. The line leaves the index (commit `Delete <name> <version>`, the file with the last one), the archive, README and docs leave `PACKAGES_DATA` (the release record stays, so the new-name cap still counts it), the package's log, the audit file and the owners' notices (the yank kind) record it, and the number is never published again: a publish of it is refused while the index history has that commit (lock files may hold its checksum). Past the window, or with a dependent, the refusal (409) says to yank it instead.

The server is one process, the only writer of `PACKAGES_DATA` and of the index checkout: run one instance.

### Data and backups

The server's records live in `PACKAGES_DATA/registry.sqlite3`, an SQLite database in WAL mode, used through the system's libsqlite3 (`src/server/sqlite.nabi`, loaded at run time; `PACKAGES_SQLITE` names another). One table per kind of record (`src/server/tables.nabi`): `accounts`, `sessions`, `tokens`, `owners`, `releases`, `trusted`, `trust_tokens`, `invites`, `locked`, `removed`, `approved`, `events` and `advisories`, each row the record's NABION in `data` under a key `k` (the account id, the session or token hash, `name@version`, ..) beside the columns lookups use; `schema_version` counts the migrations applied, which the server runs at start, and `imports` records an import. Every value reaches SQL through a prepared statement's bind. A write is one `BEGIN IMMEDIATE` transaction that changes only the rows that differ, synced to disk (`synchronous = FULL`) before the answer goes out; writers take turns under one lock, readers never wait for them. A database at a schema newer than the server is refused at start with the reason.

The files under `PACKAGES_DATA`:

| Path | What | Backed up by |
|------|------|--------------|
| `registry.sqlite3`, `registry.sqlite3-wal`, `registry.sqlite3-shm` | The database and its write-ahead log; one database, never copied apart while the server runs | `backup` (below) |
| `backup/registry-<yyyymmddhh>.sqlite3` | A copy made before the first write of each hour, the newest 72 | is a backup |
| `downloads.nabion` | Download counts, rewritten whole at most once a minute in one rename | a plain copy |
| `audit.nabion` | The audit log, one NABION line appended a change | a plain copy |
| `jwks.json` | The OIDC issuer's keys, a cache | not needed |
| `archives/`, `readme/`, `docs/` | Source archives, READMEs and docs of each version | a plain copy (`rsync`) |
| `sources/` | Git caches of the package sources | not needed (fetched again) |
| `db.nabion`, `backup/db-*.nabion` | The data before SQLite: read once, by the import, then left as they were | keep until the migration is trusted |

`nabi run -- backup <file>` (or the built program, `packages_nabi_lang_org backup <file>`) copies the live database to a new file with SQLite's online backup API, checks the copy (`PRAGMA quick_check`) and leaves it as one file (no `-wal`); it refuses a file that exists. The data directory is `--data <dir>`, else `PACKAGES_DATA` from the environment or `.env`. A nightly backup, then the rest:

```bash
# from the server's directory (its .env names PACKAGES_DATA)
packages_nabi_lang_org backup /var/backups/packages/registry-$(date -u +%Y%m%d).sqlite3
rsync -a --exclude 'registry.sqlite3*' --exclude 'sources/' "$PACKAGES_DATA/" /var/backups/packages/data/
```

Never copy `registry.sqlite3` with `cp` or `rsync` while the server runs: the last writes may be in the `-wal` file only. To restore, stop the server, put the copy in place and remove the old log:

```bash
systemctl stop packages
cp /var/backups/packages/registry-20261122.sqlite3 "$PACKAGES_DATA/registry.sqlite3"
rm -f "$PACKAGES_DATA/registry.sqlite3-wal" "$PACKAGES_DATA/registry.sqlite3-shm"
systemctl start packages
```

`nabi run -- export <file>` writes the data in db.nabion's format (`-` prints it), for a look at it or to go back to a server from before SQLite: stop the server, `export $PACKAGES_DATA/db.nabion.new`, move it over `db.nabion`, move `registry.sqlite3*` aside (a later upgrade then imports the newer `db.nabion` again) and start the old server.

A data directory with `db.nabion` and no `registry.sqlite3` (a server from before SQLite) is imported at start: everything into a new database in one transaction, built as `registry.sqlite3.import` and renamed into place, so a crash halfway leaves no database and the next start imports again. The log says what came across (`data: imported .. into ..: 2 accounts, ..`); `db.nabion` and its hourly copies are left as they were. The audit log and the download counts stay files.

Deploy as its own user with a git identity that can push to the index, behind a TLS proxy:

```caddy
packages.nabi-lang.org {
    encode gzip
    reverse_proxy 127.0.0.1:8080
}
```

## Docs

A publish makes the version's docs right away: after the index commit, from the source commit the publish just fetched and checked (scanned, never built or run). They are kept in `PACKAGES_DATA/docs/<name>/<version>/` (`status.nabion` and `api.nabion`, the modules as `nabi doc` lays them out) and handed to the docs site, which renders them at `docs.nabi-lang.org/packages/<name>/<version>`, as docs.rs does for crates.io: `GET /api/v1/docs` lists every package's versions with their commit and the state of their docs, and `GET /api/v1/packages/<name>/<version>/docs` is one version's (`PackageDocs { name, version, status, api }`). The package page's Docs tab and the Versions table link there. A site build makes the docs a version lacks (one written with `--index-dir`) and keeps them the same way; without `--data` they go to `<cache>/docs`, and `--demo` scans the fixtures in place.

A package with only an executable (`src/main.nabi`, no `src/lib.nabi`) has no docs and no Docs tab: its page shows its README and an install box with `nabi install <name>`; a package with both gets the Docs tab and a third install tab, `nabi install --bin <name>`. Lists and search mark a package with an executable `bin`. Which targets a version has comes from its tree, else from the `has_lib` and `bin_names` it was published with.

The source is untrusted, so it is only scanned (`web::apidoc`), never built or run, in a process of its own (`<program> docs ..`, `src/docs.nabi`) that is killed after 20 s; it reads at most 2000 `.nabi` files and 8 MiB under `src/`, and keeps at most 16 MiB of docs. Docs that cannot be made never fail the publish: the reply carries a `docs: ..` warning, which `nabi publish` prints, and the docs page and the Versions table show the reason. Items a `pub use` re-exports from a private module are shown inline where they are re-exported (`web::apidoc::pages`); re-exports of a public module's items link to it.

## Structured data

Each package page and tab carries JSON-LD for search engines: the package as a schema.org `SoftwareSourceCode` (name, description, version, the fetched repository as `codeRepository`, license, keywords, authors by name, `datePublished` and `dateModified` from the version dates; a version page's own version), and a `BreadcrumbList` of its trail (Packages, the package, the version, the tab); a category or keyword page has its breadcrumbs. The sitemap gives each page a `<lastmod>`: a package's pages the latest version's date, a version page its own, a category or keyword page its newest package's, the home page, the list and the two indexes the newest of all.

## Link previews

og:image and twitter:image carry `?v=<card version>`: the first 10 hex digits of the SHA-256 of what `og/render.ts` draws the card from (renderer, template, fonts, the kit's mark and `nabi.css`, the package's name, version and description; for the home card also `static/og.png`), so a changed card is a new URL. The renderer writes `<card>.png.v` with the version it drew; `serve` caches a card at that `?v=` for a year (`immutable`), anything else for an hour, and a rebuild keeps only cards whose `.v` still matches. A package page whose card is not drawn yet points at the site card (`/og.png?v=..`) instead, so after a build that changes cards run `node og/render.ts` (it skips cards already drawn) and build again. `serve` does both itself after each rebuild when `npm ci` has installed `puppeteer-core` (needs node and Chrome); otherwise new packages show the site card until a deploy draws theirs. When only a page's text changes, the cached card stays: re-scrape it with the [Facebook Sharing Debugger](https://developers.facebook.com/tools/debug/), the [LinkedIn Post Inspector](https://www.linkedin.com/post-inspector/) or Kakao's [sharing debugger](https://developers.kakao.com/tool/debugger/sharing) (clear the cache); X has no tool and refreshes in about 7 days.

## Configuration

Edit `site.nabion` (NABION). Key fields: `title`, `tagline`, `description`, `index`, `index_repo`, `base_url`, `docs`, `home`, `cache`, `out`.

## Layout

| File | Contents |
|------|----------|
| `src/main.nabi`   | Config/args, page generation, search index, link check; `serve` |
| `src/server.nabi` | `serve`: settings, responses, connections, rebuilds |
| `src/server/routes.nabi` | Which answer a request gets: search, files in `public/` and their cache rules, package 404s |
| `src/server/api.nabi` | The `/api/v1/` routes: package info, READMEs, publish, yank, owners, trusted publishers |
| `src/server/auth.nabi` | GitHub login, sessions, trusted publishing's token exchange |
| `src/server/account.nabi` | The account page and its forms |
| `src/server/owners.nabi` | Owners and trusted publishers: who may change a package |
| `src/server/store.nabi` | The data's records (accounts, sessions, tokens and their scopes, owners, releases, each package's events) and the lookups into them |
| `src/server/tables.nabi` | The data in SQLite: schema and migrations, the connection pool, reads and diffed writes, the import from `db.nabion`, backups |
| `src/server/sqlite.nabi` | The libsqlite3 binding: connections, prepared statements, transactions, the online backup |
| `src/server/github.nabi` | GitHub API calls over curl (and the curl runner SES uses) |
| `src/server/admin.nabi` | Moderation for the admins: locks, takedowns, approved names, the audit file |
| `src/server/advisories.nabi` | The advisory routes: public reads, drafts, publishing, withdrawing, the owners' notices |
| `src/osv.nabi`    | Security advisories: the OSV record, its checks, version ranges, OSV JSON both ways, the pages and banners |
| `src/server/limit.nabi` | Rate limits per address, account and token |
| `src/server/mail.nabi` | Notices by mail: who gets which, the text, the queue and its sending thread, the hourly cap |
| `src/server/aws.nabi` | Amazon SES v2 SendEmail, SigV4 signing, the instance role's credentials from IMDSv2 |
| `src/server/downloads.nabi` | Download counts: counted in memory, written once a minute |
| `src/server/img.nabi` | The image proxy: signed README image addresses, the checked fetch, the cache |
| `src/server/names.nabi` | Reserved names and the look-alike check for new ones |
| `src/server/delete.nabi` | An owner deleting a version: the 72-hour window, dependents, the files it takes away |
| `src/index.nabi`  | API entry and metadata checks, index commits and pushes |
| `src/meta.nabi`   | Per-version metadata and publisher records kept in the database |
| `src/secret.nabi` | SHA-256, random bytes, constant-time compare |
| `src/trust.nabi`  | Trusted publishing: OIDC token (JWT) checks, JWKS keys, claim matching, exchanged tokens, the bootstrap file |
| `src/json.nabi`   | The JSON GitHub answers with; NABION values written as JSON for the API |
| `src/packages.nabi` | Reads the index, semver ordering, dependents, version dates, README and source tree fetching |
| `src/apidoc.nabi` | Docs tab: public items and `///` docs scanned from a package's sources; the install box's `use` line |
| `src/docs.nabi`   | Each version's docs: made at publish in a bounded process of its own, kept with the data, their status |
| `src/layout.nabi` | Page frame (in English, Korean and Chinese), home, package list and search, category and keyword pages, publishing guide, package pages and their tabs (Readme, Docs, Versions, Dependencies, Dependents), structured data |
| `tests/`         | `e2e.sh` and the fake GitHub it runs (OAuth with PKCE, `/user`, `/user/emails`, `/repos`, an OIDC issuer that signs test tokens, AWS's IMDSv2 and SES SendEmail, and images for the proxy) |
| `pages/publishing.md` | Publishing guide text |
| `pages/api.md` | The public API's reference, at `/api` |
| `pages/policy.md`, `pages/ko/`, `pages/zh-hans/`, `pages/zh-hant/` | The usage policy (a draft, not yet reviewed) at `/policy`, and the guide, API reference and policy in Korean, Simplified and Traditional Chinese under `/ko/`, `/zh-hans/`, `/zh-hant/`; terms and privacy are nabi-lang.org's (`/terms`, `/privacy` redirect there) |
| `pages/publish.yml` | The trusted publishing workflow for a package's repository |
| `static/`        | `style.css`, `search.tsx` and its `ui/*.tsx` components, `og.png` |
| `web/`           | the web kit (submodule): `nabi.css`, `theme.js`, `keys.js`, marks and icons, and the `web` library (HTTP, addresses, header and footer markup) |
| `og/`            | Open Graph cards: `node og/render.ts` after a build, then build again |

Markdown and highlighting come from the [`markdown`](https://github.com/nabi-lang/markdown) and [`nabi-syntax`](https://github.com/nabi-lang/nabi-syntax) packages (path dependencies on `../markdown` and `../nabi-syntax` until switched to their versions on the registry).
