# packages.nabi-lang.org

[![License: MIT OR Apache-2.0](https://img.shields.io/badge/license-MIT%20OR%20Apache--2.0-blue)](LICENSE-MIT)

*Clear rules, free as a butterfly.*

Source for https://packages.nabi-lang.org, the Nabi package registry: site and server. One program written in Nabi: it reads a checkout of the registry index ([packages-index](https://github.com/nabi-lang/packages-index)) and writes a static site to `public/`; `serve` serves that site plus GitHub login, publish tokens, trusted publishing from GitHub Actions, and the publish / yank API. The server is the only writer of the index: lines enter it through the publish API, never by pull request.

## Build

Needs the Nabi toolchain (`nabi`, `nabic`), `git`, an index checkout, and the [web kit](https://github.com/nabi-lang/web) submodule at `web/` (clone with `git clone --recurse-submodules`, or run `git submodule update --init` in an existing clone). The default config assumes the repos sit side by side:

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
nabi run -- --data <dir>   # show metadata, publishers and owners from the server's db.nabion
nabi run -- serve          # serve public/ and the API (see Server)
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

## Search and browse

`/packages?q=` (served by `serve`, works without JS) and the header's search box (`static/search.tsx`, over `/search-index.json`) match alike: every term must be in the name, the description or a keyword; exact name first, then name prefix, name, keyword, the rest, official packages first among equals. When nothing matches, each term found nowhere is replaced by the nearest name, part of a name (split at `-` / `_`) or keyword within a few edits (1 for 3 to 4 characters, 2 up to 8, 3 beyond; `names::edits`, which counts a swap of two neighbours as one), and the page shows those results under "Showing results for ..": `?q=jsn` shows `json`, `?q=lnalg` shows `linalg`.

`/categories` and `/keywords` list every category and keyword the packages' latest versions name, with how many packages have each; `/categories/<slug>` and `/keywords/<slug>` list those packages, official first, then by name. The slug is the word in lowercase ASCII letters and digits, each run of anything else one `-` (`Linear Algebra` is `/keywords/linear-algebra`); a word with no letter or digit in ASCII has no page and its chip searches for it instead. The side panel's keyword and category chips link these pages; on an old version's page, whose words may have changed since, they search. They are in the sitemap like every page.

## Server

`nabi run -- serve` serves `public/` and the API over plain HTTP on `PACKAGES_ADDR` (TLS ends at a reverse proxy). Run it from this directory (reads `site.nabion` and `.env`). At start and after each index commit it rebuilds the site in the background. `GET /api/health` answers `ok`, `nabi <release>` (the toolchain the footer names) and `packages <count>`, one a line, or a 503 `failing` while the package list cannot be read.

Settings live in `.env` (copy `.env.example`; process env wins over the file):

| Variable | Meaning |
|----------|---------|
| `PACKAGES_URL` | Public base URL; OAuth callback is `{URL}/auth/github/callback` |
| `PACKAGES_ADDR` | Listen address (default `127.0.0.1:8080`) |
| `GITHUB_CLIENT_ID`, `GITHUB_CLIENT_SECRET` | The GitHub OAuth app |
| `PACKAGES_ADMINS` | Comma-separated numeric GitHub user ids (the `id` of `https://api.github.com/users/<login>`) that may create publish tokens, add trusted publishers, publish, yank and moderate. A login is refused: logins change hands, ids do not |
| `PACKAGES_OPEN_PUBLISHING` | `1` lets every account do what the admins do with their own packages; unset (default), other accounts only log in and their tokens authorize nothing |
| `PACKAGES_DATA` | Directory of `db.nabion` (accounts, tokens, owners, each version's metadata and publisher), `downloads.nabion` (download counts), `readme/<name>/<version>.md` (READMEs sent with a publish), `docs/<name>/<version>/` (docs made at publish) and `sources/` |
| `PACKAGES_INDEX` | Index checkout the server commits to and pushes from |
| `PACKAGES_TRUSTED` | Optional bootstrap file of trusted publishers (see Trusted publishing) |
| `PACKAGES_AUDIENCE` | The `aud` an OIDC token must carry (default: the host of `PACKAGES_URL`) |
| `PACKAGES_CLIENT_HEADER` | The header (`cf-connecting-ip`, `x-forwarded-for`) a trusted proxy puts the client's address in, for the rate limits; unset, the TCP peer is the client |
| `PACKAGES_RATE_LIMIT` | Changes (API writes, account forms) an account or token may make a minute (default 30); an address may make twice that |
| `PACKAGES_OFFICIAL_ORG` | GitHub's numeric id of the nabi-lang organization: versions its repositories publish through trusted publishing are official (see Official packages); unset, none are |
| `GITHUB_API_TOKEN` | Optional GitHub token (no scopes) sent with the repository and owner lookups, for 5000 requests an hour in place of 60 per address |
| `GITHUB_OAUTH_URL`, `GITHUB_API_URL`, `GITHUB_OIDC_ISSUER` | Default GitHub; tests point them at a fake |

Login is GitHub OAuth only (`read:user`) and open to anyone: the header always offers it, and an account that may not act only logs in. The account keeps GitHub's id, login, display name and avatar address from the last login; pages draw avatars from the id alone (`https://avatars.githubusercontent.com/u/<id>?s=<px>&v=4`). Pages are built logged out; for a request with a live session `serve` swaps the header's login button for an account menu (`<details>`, no script) and sends the page `no-store`. Sessions are a 32-byte cookie (`__Host-pkg_session`: this host only, https, every path) stored as SHA-256, at most 10 per account; a cookie that is not 64 hex digits is ignored before the data file is read. Publish tokens (`pkg_` + 64 hex) are admin-only until `PACKAGES_OPEN_PUBLISHING` is set, stored as SHA-256 and compared in constant time. Each lasts the days chosen when it is made (90 by default, at most 365) and may be limited to some packages; a limited token moderates nothing, even an admin's. The NABION API takes `Authorization: Bearer pkg_..`:

| Route | Purpose |
|-------|---------|
| `GET /api/v1/me` | account + publish flag |
| `POST /api/v1/publish` | `Publish { entry: Package { .. }, meta: { .. } }`: the index entry `nabi publish` prints and the package's metadata; answers `Published { name, version, file, warnings }`. A version already in the index from the same tree that was not published through the API (written by a maintainer with `nabi publish --index-dir`) gets the metadata and README it lacks instead of a 409 |
| `POST /api/v1/yank` | `Yank { name, version, undo, native, message }`; `message` (at most 512 bytes) is the reason, cleared by an unyank |
| `GET /api/v1/packages/<name>` | no token: `owners` (accounts), `orgs` (organisations and teams on record), and each `Version { version, yanked, yank_message, deps, meta, has_readme, archive, downloads, recent_downloads, published_by, yanked_by, unyanked_by, official }`, then `official` (its latest version's) and the package's `downloads` and `recent_downloads` (every version's); each actor is `Actor { id, login, at }`, plus `via` for trusted publishing; `deps` is as in the index line |
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

A package's owners (and the admins) manage its owners on the account page or through the API, like its trusted publishers; while publishing is closed only the admins do. A user is invited, and owns the package (publishes and yanks it) once they accept on their account page; invitations lapse after 30 days. An organisation or team is listed by an admin, or by an owner once one of the organisation's repositories is a trusted publisher of the package; it is shown on the package's page with the org's avatar but grants no account anything, since login asks GitHub for no membership: its members publish through trusted publishing. Every right is checked against GitHub's numeric ids, never logins. The package page also shows the owner of each trusted publisher's repository and of each trusted publish (`nabi-lang` for nabi-lang's packages), from the publisher's `owner_id` or the token's `repository_owner_id`.

An index line holds only what resolution needs, named as in the manifest: `name`, `version`, `deps`, `features`, `source`, `tree` (the commit's git tree hash), `yanked`, `toolchain`, `links`, and `official` (set by the server, below). A dependency is `{ name, req, kind, registry, optional, features, default_features, package, target }`: `package` is the package it names when `name` is a rename (as Cargo's), `target` limits it to a triple or a `cfg(..)` expression, which the client evaluates.

Index lines stay strict: a field the server does not know is refused, because every reader of the index must understand every line it resolves. The server is deployed before the clients that write a new field, so it learns the field first; a field older clients would misread also takes a higher `v` on the line.

`meta` is forward compatible instead. The known keys are the manifest's descriptive fields (`description`, `license`, `license_file`, `authors`, `homepage`, `documentation`, `repository`, `readme`, `keywords`, `categories`, `include`, `exclude`, `publish`, `metadata`, `links`, `default_run`), what the client measured (`has_lib`, `bin_names`, `size`: packed bytes) and `readme_content` (the README text, at most 512 KiB). They are checked; any other key is kept as sent (at most 32 keys, 16 KiB), returned in the API with the rest, and named in the reply's `warnings`, never refused. The metadata is kept in `db.nabion` with the account and time of the publish, yank and unyank; the README text in its own file, shown on the package page in place of the commit's README.

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

A publish checks the source before it takes any lock: the address must be https on a public host (no IP address, port, user name or `localhost`), and each source has a git cache of its own under `PACKAGES_DATA/sources/git/`, fetched over https only (`GIT_ALLOW_PROTOCOL`, which the process environment may widen for tests), without redirects, within 120 s, giving up below 1 KiB/s, and with each file it writes capped at about 256 MiB. The commit must be the tip of a branch or tag of that repository, or an ancestor of one: GitHub serves a fork's commits through the parent's address too, so a fetch alone proves nothing. Then `INDEX` covers the index write (reset to upstream, append or flip `yanked`, commit as the publishing account, push, each git step within 60 s; a failed push resets and answers 503), and `LOCK`, inside it, the data file's read and write. Reads take the data file without a lock: it is replaced in one rename. Docs are made after both are released. Entry and metadata validation, the source checks and archives, and the commit flow are in `src/index.nabi`.

New names are checked too: at most 64 characters, not reserved (`src/server/names.nabi`: the toolchain's and the standard library's names, `nabi-*`, `std-*`, `core-*`), not an official package's name or a look-alike of one (the nabi-lang organization's packages, `names::FIRST_PARTY`, and every package with an official version), and not a look-alike of a name in the index (one edit apart for names of four or more characters, or the same once case, `-` / `_`, `0` / `o`, `1` / `l` / `i`, `5` / `s`, `rn` / `m` and `vv` / `w` are folded), unless an admin approves it; an account takes at most 10 new names a day. Rate limits (`src/server/limit.nabi`) count in memory: logins 20 a minute per address, changes `PACKAGES_RATE_LIMIT` a minute per account or token and twice that per address, trusted publishing exchanges 20 a minute per address; past them the answer is a 429 with `Retry-After`. Moderation steps, logins and logouts, and changes to tokens, owners, invitations and trusted publishers are logged and appended to `PACKAGES_DATA/audit.nabion` (`Audit { at, by, action, target, reason }`, `by` a GitHub id).

The server is one process, the only writer of `PACKAGES_DATA` and of the index checkout: run one instance. `db.nabion` is written whole to a temporary file and renamed into place; before the first write of each hour the old file is kept as `PACKAGES_DATA/backup/db-<yyyymmddhh>.nabion` (the newest 72). Copy `PACKAGES_DATA` off the machine as well (it holds the archives, READMEs and docs), for example with a nightly `rsync`.

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
| `src/server/store.nabi` | `db.nabion`: accounts, sessions, tokens, owners, releases |
| `src/server/github.nabi` | GitHub API calls over curl |
| `src/server/admin.nabi` | Moderation for the admins: locks, takedowns, approved names, the audit file |
| `src/server/limit.nabi` | Rate limits per address, account and token |
| `src/server/downloads.nabi` | Download counts: counted in memory, written once a minute |
| `src/server/names.nabi` | Reserved names and the look-alike check for new ones |
| `src/index.nabi`  | API entry and metadata checks, index commits and pushes |
| `src/meta.nabi`   | Per-version metadata and publisher records kept in `db.nabion` |
| `src/secret.nabi` | SHA-256, random bytes, constant-time compare |
| `src/trust.nabi`  | Trusted publishing: OIDC token (JWT) checks, JWKS keys, claim matching, exchanged tokens, the bootstrap file |
| `src/json.nabi`   | The JSON GitHub answers with |
| `src/packages.nabi` | Reads the index, semver ordering, dependents, version dates, README and source tree fetching |
| `src/apidoc.nabi` | Docs tab: public items and `///` docs scanned from a package's sources; the install box's `use` line |
| `src/docs.nabi`   | Each version's docs: made at publish in a bounded process of its own, kept with the data, their status |
| `src/layout.nabi` | Page frame, home, package list and search, category and keyword pages, publishing guide, package pages and their tabs (Readme, Docs, Versions, Dependencies, Dependents) |
| `tests/`         | `e2e.sh` and the fake GitHub it runs (OAuth, `/user`, `/repos`, an OIDC issuer that signs test tokens) |
| `pages/publishing.md` | Publishing guide text |
| `pages/{terms,privacy,policy}.md`, `pages/ko/` | Terms of use, privacy notice and usage policy (drafts, not yet reviewed), at `/terms`, `/privacy`, `/policy` and in Korean under `/ko/` |
| `pages/publish.yml` | The trusted publishing workflow for a package's repository |
| `static/`        | `style.css`, `search.tsx` and its `ui/*.tsx` components, `og.png` |
| `web/`           | the web kit (submodule): `nabi.css`, `theme.js`, `keys.js`, marks and icons, and the `web` library (HTTP, addresses, header and footer markup) |
| `og/`            | Open Graph cards: `node og/render.ts` after a build, then build again |

Markdown and highlighting come from the [`markdown`](https://github.com/nabi-lang/markdown) and [`nabi-syntax`](https://github.com/nabi-lang/nabi-syntax) packages (path dependencies on `../markdown` and `../nabi-syntax` until switched to their versions on the registry).
