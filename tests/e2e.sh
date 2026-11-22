#!/usr/bin/env bash
# End-to-end test of `nabi run -- serve`: a temp index (bare remote +
# checkout), a fake GitHub (tests/fake-github), logins through the OAuth
# callback, publish tokens, trusted publishing with the fake's OIDC
# tokens, the API, and the commits pushed to the index.
#
#   tests/e2e.sh            (needs nabi, nabic, git, curl on PATH)
#
# Everything lives in a temp directory, removed at the end.
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/packages-e2e.XXXXXX")
pids=()
cleanup() {
    for p in "${pids[@]}"; do kill "$p" 2>/dev/null || true; done
    # A site rebuild the server started may still be writing.
    rm -rf "$T" 2>/dev/null || { sleep 1; rm -rf "$T"; }
}
trap cleanup EXIT

fail() { echo "FAIL: $*" >&2; echo "--- server log" >&2; tail -30 "$T/server.log" >&2 || true; exit 1; }
ok() { echo "ok: $*"; }

(cd "$repo" && nabi build >/dev/null)
(cd "$repo/tests/fake-github" && nabi build >/dev/null)
bin="$repo/target/debug/packages_nabi_lang_org"

gh_port=$((20000 + RANDOM % 5000))
port=$((25000 + RANDOM % 5000))
base="http://127.0.0.1:$port"

# The index: a bare remote and the server's checkout of it.
git init -q --bare "$T/remote.git"
git clone -q "$T/remote.git" "$T/index" 2>/dev/null
git -C "$T/index" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
git -C "$T/index" push -q -u origin HEAD 2>/dev/null

# A site directory: the generator's inputs, output in $T/site/public.
mkdir -p "$T/site"
cp -R "$repo/static" "$repo/pages" "$T/site/"
mkdir -p "$T/site/og"
cp -R "$repo/og/render.ts" "$repo/og/home.html" "$repo/og/package.html" "$repo/og/fonts" "$T/site/og/"
mkdir -p "$T/site/web/assets"
cp -R "$repo/web/assets/fonts" "$T/site/web/assets/"
sed -e 's|^ *out: .*|    out: "public",|' "$repo/site.nabion" > "$T/site/site.nabion"

cat > "$T/trusted.nabion" <<'EOF'
// as infra writes it
[
    TrustedPublisher { package: "seeded", repository: "acme/seeded", owner_id: 4242, workflow: "publish.yml" },
]
EOF

"$repo/tests/fake-github/target/debug/fake_github" "127.0.0.1:$gh_port" test-secret &
pids+=($!)
# A source host that takes connections and never answers.
slow_port=$((30000 + RANDOM % 5000))
if command -v python3 >/dev/null; then
    python3 -c 'import socket, sys, time
s = socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1); s.bind(("127.0.0.1", int(sys.argv[1]))); s.listen(16)
held = []
while True: held.append(s.accept()[0])' "$slow_port" &
    pids+=($!)
fi

start_server() {
    (cd "$T/site" && exec env \
        PACKAGES_URL="https://packages.test" \
        PACKAGES_ADDR="127.0.0.1:$port" \
        GITHUB_CLIENT_ID="test-client" \
        GITHUB_CLIENT_SECRET="test-secret" \
        PACKAGES_ADMINS="$1" \
        PACKAGES_DATA="$T/data" \
        PACKAGES_INDEX="$T/index" \
        GITHUB_OAUTH_URL="http://127.0.0.1:$gh_port" \
        GITHUB_API_URL="http://127.0.0.1:$gh_port" \
        GITHUB_OIDC_ISSUER="http://127.0.0.1:$gh_port/oidc" \
        PACKAGES_TRUSTED="$T/trusted.nabion" \
        GIT_ALLOW_PROTOCOL=https:file:http \
        PACKAGES_RATE_LIMIT=1000 \
        PACKAGES_OFFICIAL_ORG=5151 \
        GIT_CONFIG_COUNT=2 \
        GIT_CONFIG_KEY_0="url.file://$T/src/.insteadOf" \
        GIT_CONFIG_VALUE_0="https://example.invalid/" \
        GIT_CONFIG_KEY_1="url.http://127.0.0.1:$slow_port/.insteadOf" \
        GIT_CONFIG_VALUE_1="https://slow.invalid/" \
        "$bin" serve >>"$T/server.log" 2>&1) &
    server=$!
    pids+=($server)
    for _ in $(seq 50); do
        curl -s -o /dev/null "$base/login" && return 0
        sleep 0.1
    done
    fail "server did not start"
}

# req METHOD PATH [curl args..]: sets $code; headers in $T/h, body in $T/b.
req() {
    local m=$1 p=$2
    shift 2
    code=$(curl -s -X "$m" -D "$T/h" -o "$T/b" -w '%{http_code}' "$@" "$base$p")
}
header() { grep -i "^$1:" "$T/h" | head -1 | sed -e 's/^[^:]*: *//' -e 's/\r$//'; }
cookie_of() { grep -i "^set-cookie: $1=" "$T/h" | head -1 | sed -e "s/^[^=]*=//" -e 's/;.*//'; }
expect_code() { [ "$code" = "$1" ] || fail "$2: HTTP $code, want $1: $(head -c 300 "$T/b")"; }
expect_body() { grep -q -- "$1" "$T/b" || fail "$2: body lacks $1: $(head -c 300 "$T/b")"; }

# login CODE: logs in through the callback; sets $sess and $csrf.
login() {
    req GET /login
    expect_code 303 "login redirect"
    local loc state
    loc=$(header location)
    state=$(cookie_of __Host-pkg_state)
    case "$loc" in
        "http://127.0.0.1:$gh_port/login/oauth/authorize?client_id=test-client&"*"state=$state&scope=read:user") ;;
        *) fail "authorize url: $loc" ;;
    esac
    header set-cookie | grep -q "^__Host-pkg_state=[0-9a-f]*; Path=/; Max-Age=600; HttpOnly; Secure; SameSite=Lax" || fail "state cookie flags: $(header set-cookie)"
    req GET "/auth/github/callback?code=$1&state=$state" -H "Cookie: __Host-pkg_state=wrong"
    expect_code 400 "state mismatch"
    req GET "/auth/github/callback?code=$1&state=$state" -H "Cookie: __Host-pkg_state=$state"
    expect_code 303 "callback"
    sess=$(cookie_of __Host-pkg_session)
    [ ${#sess} = 64 ] || fail "session cookie"
    req GET /me -H "Cookie: __Host-pkg_session=$sess"
    expect_code 200 "/me"
    code=$(curl -s -I -o /dev/null -w '%{http_code}' -H "Cookie: __Host-pkg_session=$sess" "$base/me")
    [ "$code" = 200 ] || fail "HEAD /me: $code, want 200"
    csrf=$(sed -n 's/.*name="csrf" value="\([0-9a-f]*\)".*/\1/p' "$T/b" | head -1)
    [ -n "$csrf" ] || fail "no csrf token on /me"
}

start_server 1001

for _ in $(seq 100); do [ -f "$T/site/public/index.html" ] && break; sleep 0.2; done
req GET /
expect_code 200 "home page"
[ "$(header content-type)" = "text/html; charset=utf-8" ] || fail "html type"
[ "$(header strict-transport-security)" = "max-age=63072000; includeSubDomains" ] || fail "hsts: $(header strict-transport-security)"
[ "$(header referrer-policy)" = "strict-origin-when-cross-origin" ] || fail "referrer policy"
header permissions-policy | grep -q 'camera=()' || fail "permissions policy"
req GET /style.css
[ "$(header content-type)" = "text/css; charset=utf-8" ] || fail "css type"
mkdir -p "$T/site/public/empty"
req GET /empty/
expect_code 301 "trailing slash"
[ "$(header location)" = "/empty" ] || fail "trailing slash location: $(header location)"
req GET /empty
expect_code 404 "no directory listing"
req GET "/index.html?a=1&b=2"
expect_code 301 "index.html"
[ "$(header location)" = "/?a=1&b=2" ] || fail "index.html location: $(header location)"
req GET /publishing.html
[ "$code" = 301 ] && [ "$(header location)" = "/publishing" ] || fail "publishing.html: $code $(header location)"
req GET /publishing
expect_code 200 "extensionless page"
code=$(curl -s -o /dev/null -w '%{http_code}' --path-as-is "$base/../site.nabion")
[ "$code" = 400 ] || [ "$code" = 404 ] || fail "path traversal: $code"
code=$(curl -s -o /dev/null -w '%{http_code}' --path-as-is "$base/%2e%2e/site.nabion")
[ "$code" = 404 ] || fail "encoded traversal: $code"
v=$(sed -n 's|.*property="og:image" content="[^"]*/og.png?v=\([0-9a-f]\{10\}\)".*|\1|p' "$T/site/public/index.html")
[ -n "$v" ] || fail "no versioned og:image"
req GET /og.png
[ "$(header cache-control)" = "public, max-age=0, s-maxage=86400, stale-if-error=86400" ] || fail "bare og.png cache: $(header cache-control)"
echo "$v" > "$T/site/public/og.png.v"
req GET "/og.png?v=$v"
[ "$(header cache-control)" = "public, max-age=31536000, immutable" ] || fail "versioned og.png cache: $(header cache-control)"
req GET "/og.png?v=0000000000"
[ "$(header cache-control)" = "public, max-age=0, s-maxage=86400, stale-if-error=86400" ] || fail "stale og.png cache: $(header cache-control)"
req GET /style.css
[ "$(header cache-control)" = "public, max-age=0, s-maxage=86400, stale-if-error=86400" ] || fail "css cache: $(header cache-control)"
css=$(grep -o '/style.css?v=[0-9a-f]\{10\}' "$T/site/public/index.html" | head -1)
[ -n "$css" ] || fail "no versioned style.css"
req GET "$css"
[ "$(header cache-control)" = "public, max-age=31536000, immutable" ] || fail "versioned css cache: $(header cache-control)"
req GET /publishing
[ "$(header cache-control)" = "public, max-age=0, s-maxage=86400, stale-if-error=86400" ] || fail "page cache: $(header cache-control)"
etag=$(header etag)
[ -n "$etag" ] || fail "no etag"
rm -f "$T/b"
req GET /publishing -H "If-None-Match: $etag"
expect_code 304 "if-none-match"
[ ! -s "$T/b" ] || fail "304 with a body"
req GET /fonts/Geist-Variable.woff2
expect_code 200 "font"
[ "$(header content-type)" = "font/woff2" ] || fail "font type: $(header content-type)"
[ "$(header cache-control)" = "public, max-age=31536000, immutable" ] || fail "font cache: $(header cache-control)"
req GET /fonts/pretendard.css
[ "$(header content-type)" = "text/css; charset=utf-8" ] || fail "pretendard.css type: $(header content-type)"
grep -q 'googleapis\|jsdelivr' "$T/site/public/index.html" && fail "third-party fonts"
grep -q '<a class="btn-2 btn-sm login" href="/login">Log in<span class="wide"> with GitHub</span></a>' "$T/site/public/index.html" || fail "no login button"
req GET /
expect_body 'href="/login">Log in' "login button logged out"
[ "$(header vary)" = "Cookie" ] || fail "html vary: $(header vary)"
req GET / -H "Cookie: __Host-pkg_session=$(printf 'ab%.0s' $(seq 32))"
expect_body 'href="/login">Log in' "login button with a dead session"
[ "$(header cache-control)" = "public, max-age=0, s-maxage=86400, stale-if-error=86400" ] || fail "dead session cache: $(header cache-control)"
req GET /.well-known/security.txt
expect_code 200 "security.txt"
expect_body 'Contact: mailto:security@nabi-lang.org' "security.txt contact"
req GET /privacy
expect_code 301 "privacy moved"
[ "$(header location)" = https://nabi-lang.org/privacy ] || fail "privacy location: $(header location)"
ok "static files"

# CSP reports: anyone may send them, so an address's past 30 a minute
# are answered alike and not logged.
report='{"csp-report":{"effective-directive":"script-src","blocked-uri":"https://csp-flood.test/x","document-uri":"https://packages.test/"}}'
for _ in $(seq 35); do
    req POST /_csp -H "Content-Type: application/csp-report" --data "$report"
    expect_code 204 "csp report"
done
n=$(grep -c 'csp: script-src blocked https://csp-flood.test/x' "$T/server.log")
[ "$n" = 30 ] || fail "csp reports logged: $n, want 30"
req GET /_csp
expect_code 405 "csp report GET"
ok "csp reports"

# HEAD /me answers as GET does: logged out, the way to log in.
code=$(curl -s -I -o /dev/null -w '%{http_code}' "$base/me")
[ "$code" = 303 ] || fail "HEAD /me logged out: $code, want 303"

login user
expect_body "Publishing is not open yet" "non-admin page"
expect_body 'come from your GitHub account' "profile note"
expect_body 'Logged in with GitHub as <a href="https://github.com/Bob"><strong>Bob</strong></a>' "non-admin profile"
grep -q 'action="/me/owners"' "$T/b" && fail "owner form offered to a non-admin"
bob_sess=$sess bob_csrf=$csrf
req GET / -H "Cookie: __Host-pkg_session=$bob_sess"
expect_code 200 "home logged in"
grep -q 'href="/login"' "$T/b" && fail "login button while logged in"
expect_body '<details class="user"><summary class="btn-2 btn-sm" aria-label="Account menu of Bob"><img class="av" src="https://avatars.githubusercontent.com/u/1002?s=40&v=4"' "header avatar"
expect_body "action=\"/logout\"><input type=\"hidden\" name=\"csrf\" value=\"$bob_csrf\">" "header log out"
[ "$(header cache-control)" = "no-store" ] || fail "logged-in page cache: $(header cache-control)"
[ -z "$(header etag)" ] || fail "logged-in page etag"
req GET /publishing -H "Cookie: __Host-pkg_session=$bob_sess"
expect_body 'href="/me">Account</a>' "menu on a static page"
req POST /me/tokens -H "Cookie: __Host-pkg_session=$bob_sess" --data "csrf=$bob_csrf&name=x"
expect_code 403 "non-admin token"
expect_body "not open yet" "non-admin token message"
req GET /me -H "Cookie: __Host-pkg_session=$bob_sess"
expect_code 200 "non-admin logged in"
grep -q 'action="/me/tokens"\|action="/me/trusted"' "$T/b" && fail "forms offered to a non-admin"
req POST /me/trusted -H "Cookie: __Host-pkg_session=$bob_sess" --data "csrf=$bob_csrf&package=geom&repository=acme/geom&workflow=publish.yml"
expect_code 403 "non-admin trusted publisher"
expect_body "not open yet" "non-admin trusted publisher message"
req POST /me/owners -H "Cookie: __Host-pkg_session=$bob_sess" --data "csrf=$bob_csrf&package=geom&login=Bob"
expect_code 403 "non-admin adds an owner"
expect_body "not open yet" "non-admin owner message"
req POST /me/owners/remove -H "Cookie: __Host-pkg_session=$bob_sess" --data "csrf=$bob_csrf&package=geom&login=alice"
expect_code 403 "non-admin removes an owner"
ok "non-admin cannot get a token"

login admin
expect_body "<strong>alice</strong>" "admin page"
expect_body '<img class="av" src="https://avatars.githubusercontent.com/u/1001?s=160&v=4" width="80" height="80"' "profile avatar"
expect_body '<p class="t-h3">Alice Liddell</p>' "profile name"
grep -q 'name: "Alice Liddell"' "$T/data/db.nabion" && grep -q 'avatar_url: "https://avatars.githubusercontent.com/u/1001?v=4"' "$T/data/db.nabion" || fail "account name and avatar not stored"
req POST /me/tokens -H "Cookie: __Host-pkg_session=$sess" --data "name=ci"
expect_code 403 "token without csrf"
req POST /me/tokens -H "Cookie: __Host-pkg_session=$sess" --data "csrf=$bob_csrf&name=ci"
expect_code 403 "token with another session's csrf"
req POST /me/tokens -H "Cookie: __Host-pkg_session=$sess" --data "csrf=$csrf&name=ci"
expect_code 200 "create token"
tok=$(grep -o 'pkg_[0-9a-f]\{64\}' "$T/b" | head -1)
[ -n "$tok" ] || fail "token not shown"
grep -q "$tok" "$T/data/db.nabion" && fail "token stored in clear"
req GET /me -H "Cookie: __Host-pkg_session=$sess"
grep -q "$tok" "$T/b" && fail "token shown twice"
expect_body "<td>ci</td>" "token listed"
req POST /me/tokens -H "Cookie: __Host-pkg_session=$sess" --data "csrf=$csrf&name=long&days=400"
expect_code 400 "token lifetime cap"
req POST /me/tokens -H "Cookie: __Host-pkg_session=$sess" --data "csrf=$csrf&name=bad&packages=a%2Fb"
expect_code 400 "token package list"
req POST /me/tokens -H "Cookie: __Host-pkg_session=$sess" --data "csrf=$csrf&name=one&packages=Ge-Om&days=7"
expect_code 200 "limited token"
one=$(grep -o 'pkg_[0-9a-f]\{64\}' "$T/b" | head -1)
expect_body '<td class="mono">ge_om</td>' "limited token listed"
grep -q '"token-create"' "$T/data/audit.nabion" || fail "token creation audited"
ok "admin token"

auth=(-H "Authorization: Bearer $tok")
req GET /api/v1/me "${auth[@]}"
expect_code 200 "api me"
expect_body 'Me { login: "alice", publish: true }' "api me body"
req GET /api/v1/me -H "Authorization: Bearer pkg_$(printf '0%.0s' $(seq 64))"
expect_code 401 "bad token"
expect_body 'Error { message:' "error body"
req POST /api/v1/me "${auth[@]}"
expect_code 405 "method"

# Package sources: https://example.invalid/<name> is $T/src/<name> (the
# server's git config above). `geom` is a library, `app` is not.
source_repo() {
    mkdir -p "$T/src/$1/src"
    echo 'pub fn f() -> i32 { 1 }' > "$T/src/$1/src/$2"
    git -C "$T/src/$1" init -q
    git -C "$T/src/$1" add -A
    git -C "$T/src/$1" -c user.name=t -c user.email=t@t commit -q -m init
    git -C "$T/src/$1" rev-parse HEAD
}
rev=$(source_repo geom lib.nabi)
tree=$(git -C "$T/src/geom" rev-parse "HEAD^{tree}")
app_rev=$(source_repo app main.nabi)
line="Package { name: \"geom\", version: \"0.1.0\", deps: [], source: Dep::git(\"https://example.invalid/geom\", rev: \"$rev\"), tree: \"$tree\", yanked: false, nabi_version: \"0.2.0\" }"
meta='{ description: "Shapes", license: "MIT", authors: ["Ann <ann@example.org>"], keywords: ["geometry"], categories: ["mathematics"], metadata: { docs: { all: true } } }'
# publish LINE [META]: the body `nabi publish` sends.
publish() {
    if [ $# -gt 1 ]; then
        req POST /api/v1/publish "${auth[@]}" --data-binary "Publish { entry: $1, meta: $2 }"
    else
        req POST /api/v1/publish "${auth[@]}" --data-binary "Publish { entry: $1 }"
    fi
}
publish "$line" "$meta"
expect_code 200 "publish"
expect_body 'Published { name: "geom", version: "0.1.0", file: "ge/om/geom", warnings: \[\] }' "publish body"
[ "$(git -C "$T/remote.git" log -1 --format=%s)" = "Publish geom 0.1.0" ] || fail "pushed commit"
[ "$(git -C "$T/remote.git" log -1 --format='%an <%ae>')" = "alice <1001+alice@users.noreply.github.com>" ] || fail "commit author"
# The server adds the archive's SHA-256 after `tree`.
sent() { sed -E 's/, archive: "[0-9a-f]{64}"//'; }
git -C "$T/remote.git" show HEAD:ge/om/geom | grep -Eq "tree: \"$tree\", archive: \"[0-9a-f]{64}\", yanked" || fail "index line archive"
[ "$(git -C "$T/remote.git" show HEAD:ge/om/geom | sent)" = "$line" ] || fail "index line"
# The rebuild draws no card (no puppeteer-core): the page gets the site card.
for _ in $(seq 50); do [ -f "$T/site/public/packages/geom.html" ] && break; sleep 0.1; done
grep -q 'property="og:image" content="[^"]*/og.png?v=[0-9a-f]\{10\}"' "$T/site/public/packages/geom.html" || fail "undrawn card falls back to og.png"
publish "$line"
expect_code 409 "republish"
publish "${line//\"geom\"/\"ge-om\"}"
expect_code 200 "second name"
publish "${line//\"geom\"/\"ge_om\"}"
expect_code 409 "spelling conflict"
publish "${line//https:/http:}"
expect_code 400 "http source"
publish "${line//geom/Geom}"
expect_code 400 "name rule"
publish "${line//yanked: false/yanked: false, x: 1}"
expect_code 400 "unknown field"
publish "${line//version:/vers:}"
expect_code 400 "0.1 field names"
req POST /api/v1/publish "${auth[@]}" --data-binary "$line"
expect_code 400 "bare entry"
publish "${line//0.1.0/0.1.1}" '{ homepage: "ftp://x" }'
expect_code 400 "bad metadata"
# A rename, a target-only dependency, the targets, the packed size, the
# README text and a key this server does not know.
line2=${line//0.1.0/0.1.2}
dep='{ name: "shapes", req: "^0.1", kind: "normal", package: "ge-om", target: "cfg(unix)" }'
line2=${line2//deps: \[\]/deps: [$dep]}
publish "$line2" '{ description: "Shapes", categories: ["mathematics"], has_lib: true, bin_names: ["geom-cli"], size: 4096, readme_content: "# geom\n\nShapes, **fast**.\n", future_key: { a: 1 } }'
expect_code 200 "publish with new metadata"
expect_body 'warnings: \["meta: `future_key` is not known to this registry; kept as sent"\]' "unknown key warning"
[ "$(git -C "$T/remote.git" show HEAD:ge/om/geom | tail -1 | sent)" = "$line2" ] || fail "rename line"
publish "${line2//cfg(unix)/cfg(unix}"
expect_code 400 "bad target"
publish "${line//0.1.0/0.1.3}" "{ readme_content: \"$(head -c 524289 /dev/zero | tr '\0' a)\" }"
expect_code 400 "readme cap"
req POST /api/v1/publish --data-binary "Publish { entry: $line }"
expect_code 401 "no token"
# An executable alone is a package; a tree with neither target is not.
app_tree=$(git -C "$T/src/app" rev-parse "HEAD^{tree}")
app_line="Package { name: \"app\", version: \"0.1.0\", deps: [], source: Dep::git(\"https://example.invalid/app\", rev: \"$app_rev\"), tree: \"$app_tree\", yanked: false, nabi_version: \"0.2.0\" }"
publish "$app_line" '{ description: "A tool", has_lib: false, bin_names: ["app"] }'
expect_code 200 "publish an executable"
util_rev=$(source_repo util util.nabi)
util_line=${line//example.invalid\/geom/example.invalid\/util}
util_line=${util_line//\"geom\"/\"util\"}
publish "${util_line//$rev/$util_rev}"
expect_code 400 "not a package"
expect_body 'not a package: no src/lib.nabi (a library) or src/main.nabi (an executable)' "not a package body"
publish "${line//$rev/$(printf 'cd%.0s' $(seq 20))}"
expect_code 400 "unfetchable source"
publish "${line//tree: \"$tree\"/tree: \"$rev\"}"
expect_code 400 "tree mismatch"
expect_body "\`tree\` $rev is not the tree hash of commit $rev ($tree)" "tree mismatch body"
h=$(printf 'ab%.0s' $(seq 32))
native="Native { name: \"zlib\", version: \"1.3.1\", deps: {}, targets: { \"x86_64-unknown-linux-gnu\": Artifact { url: \"https://example.invalid/z.tar.gz\", sha256: \"$h\", links: { \"z\": \"static\" }, runtime: [] } }, yanked: false }"
publish "$native" '{ license: "Zlib" }'
expect_code 200 "publish native"
[ "$(git -C "$T/remote.git" show HEAD:native/zl/ib/zlib)" = "$native" ] || fail "native line"
ok "publish"

# Docs: `nabi publish` against this server makes the version's docs from
# its source (scanned, never built), kept in the data and handed to the
# docs site by the API (GET /api/v1/docs, /api/v1/packages/<n>/<v>/docs),
# which renders them at docs.nabi-lang.org/packages/<name>/<version>.
git clone -q "$T/remote.git" "$T/index2" 2>/dev/null
echo "Config { api: \"$base\" }" > "$T/index2/config.nabion"
git -C "$T/index2" add config.nabion
git -C "$T/index2" -c user.name=t -c user.email=t@t commit -q -m config
git -C "$T/index2" push -q origin HEAD 2>/dev/null
mkdir -p "$T/src/shapes/src/shapes"
cat > "$T/src/shapes/nabi.nabion" <<'EOF2'
Package {
    name: "shapes",
    version: "0.2.0",
    nabi_version: "0.1.0",
    license: "MIT",
}
EOF2
printf '# shapes\n\nPlane shapes.\n' > "$T/src/shapes/README.md"
cat > "$T/src/shapes/src/lib.nabi" <<'EOF2'
//! Plane shapes.

pub mod units;

mod shapes;

pub use shapes::{Circle, area as area_of};
pub use units::Meter;
EOF2
cat > "$T/src/shapes/src/shapes.nabi" <<'EOF2'
/// A circle.
pub struct Circle {
    /// Its radius.
    pub r: f64;
}

impl Circle {
    /// The circle of radius `r`.
    pub fn new(r: f64) -> Circle { Circle { r: r } }
}

/// The area of `c`.
pub fn area(c: Circle) -> f64 { 3.14 * c.r * c.r }
EOF2
echo 'pub struct Meter {}' > "$T/src/shapes/src/units.nabi"
git -C "$T/src/shapes" init -q
git -C "$T/src/shapes" remote add origin https://example.invalid/shapes
git -C "$T/src/shapes" add -A
git -C "$T/src/shapes" -c user.name=t -c user.email=t@t commit -q -m init
nabi_client() {
    (cd "$T/src/shapes" && env NABI_HOME="$T/nabi-home" GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0="url.file://$T/src/.insteadOf" GIT_CONFIG_VALUE_0="https://example.invalid/" nabi "$@")
}
echo "$tok" | nabi_client login --registry "file://$T/remote.git" >"$T/client.log" 2>&1 || fail "nabi login: $(cat "$T/client.log")"
nabi_client publish --registry "file://$T/remote.git" >"$T/client.log" 2>&1 || fail "nabi publish: $(cat "$T/client.log")"
grep -q "Published shapes 0.2.0" "$T/client.log" || fail "nabi publish output: $(cat "$T/client.log")"
grep -q "docs:" "$T/client.log" && fail "docs warning on a good publish: $(cat "$T/client.log")"
grep -q 'Status { state: "ok"' "$T/data/docs/shapes/0.2.0/status.nabion" || fail "docs status: $(cat "$T/data/docs/shapes/0.2.0/status.nabion")"
grep -q 'Circle' "$T/data/docs/shapes/0.2.0/api.nabion" || fail "docs kept"
req GET /api/v1/packages/shapes/0.2.0/docs
expect_code 200 "version docs"
expect_body 'PackageDocs { name: "shapes", version: "0.2.0", status: Status { state: "ok"' "docs status"
# Inline: the private module's items as the root's own, renamed, with
# their members; the public module's item stays a re-export.
expect_body 'path: "shapes",' "root module"
expect_body 'name: "Circle"' "inline re-export"
expect_body 'name: "area_of"' "renamed re-export"
expect_body 'path: "shapes::units"' "child module"
req GET /api/v1/packages/shapes/9.9.9/docs
expect_code 404 "no docs of a version not published"
req GET /api/v1/docs
expect_code 200 "docs index"
expect_body 'name: "shapes",' "docs index entry"
expect_body 'description: "Shapes",' "docs index description"
expect_body 'docs: "ok"' "docs index version"
req GET /docs/shapes/0.2.0
expect_code 404 "no docs pages on the registry"
for _ in $(seq 100); do grep -q '0.2.0' "$T/site/public/packages/shapes.html" 2>/dev/null && break; sleep 0.1; done
req GET /packages/shapes
expect_body '/packages/shapes/latest">Docs <span aria-hidden="true">' "docs tab links to the docs site"
req GET /packages/shapes/versions
expect_body '/packages/shapes/0.2.0">docs</a>' "docs in the versions table"
# A scan that fails does not stop the publish; the page says why.
cp "$T/src/shapes/src/lib.nabi" "$T/lib.keep"
head -c 9000000 /dev/zero | tr '\0' ' ' >> "$T/src/shapes/src/lib.nabi"
sed -i.bak -e 's/0.2.0/0.2.1/' "$T/src/shapes/nabi.nabion" && rm "$T/src/shapes/nabi.nabion.bak"
git -C "$T/src/shapes" -c user.name=t -c user.email=t@t commit -q -am big
nabi_client publish --registry "file://$T/remote.git" >"$T/client.log" 2>&1 || fail "nabi publish of a big package: $(cat "$T/client.log")"
grep -q "docs: src/ has [0-9]* bytes of .nabi; docs are made for at most 8388608" "$T/client.log" || fail "docs warning: $(cat "$T/client.log")"
req GET /api/v1/packages/shapes/0.2.1/docs
expect_code 200 "failed docs"
expect_body 'state: "failed",' "failed docs status"
expect_body 'message: "src/ has' "failed docs reason"
for _ in $(seq 100); do grep -q 'shapes/0.2.1" class="tag"' "$T/site/public/packages/shapes/versions.html" 2>/dev/null && break; sleep 0.1; done
req GET /packages/shapes/versions
expect_body '/packages/shapes/0.2.1" class="tag" title="src/ has' "failed docs in the versions table"
ok "docs"

req POST /api/v1/yank "${auth[@]}" --data-binary 'Yank { name: "geom", version: "0.1.0", message: "wrong areas" }'
expect_code 200 "yank"
expect_body 'Yanked { name: "geom", version: "0.1.0", yanked: true }' "yank body"
[ "$(git -C "$T/remote.git" log -1 --format=%s)" = "Yank geom 0.1.0" ] || fail "yank commit"
git -C "$T/remote.git" show HEAD:ge/om/geom | grep -q 'yanked: true' || fail "yanked line"
req GET /api/v1/packages/geom
expect_body 'version: "0.1.0", yanked: true, yank_message: "wrong areas"' "yank message"
req POST /api/v1/yank "${auth[@]}" --data-binary 'Yank { name: "geom", version: "0.1.0", undo: true, message: "x" }'
expect_code 400 "unyank with a message"
req POST /api/v1/yank "${auth[@]}" --data-binary 'Yank { name: "geom", version: "0.1.0", undo: true, native: false }'
expect_code 200 "unyank"
[ "$(git -C "$T/remote.git" log -1 --format=%s)" = "Unyank geom 0.1.0" ] || fail "unyank commit"
[ "$(git -C "$T/remote.git" show HEAD:ge/om/geom | head -1 | sent)" = "$line" ] || fail "unyanked line"
req POST /api/v1/yank "${auth[@]}" --data-binary 'Yank { name: "zlib", version: "1.3.1", native: true }'
[ "$(git -C "$T/remote.git" log -1 --format=%s)" = "Yank native zlib 1.3.1" ] || fail "native yank commit"
req POST /api/v1/yank "${auth[@]}" --data-binary 'Yank { name: "geom", version: "9.9.9" }'
expect_code 404 "yank unknown"
ok "yank"

# Metadata and who did what: the public API, no token.
req GET /api/v1/packages/geom
expect_code 200 "package api"
expect_body 'Package { name: "geom", native: false, owners: \[{ id: 1001, login: "alice" }\]' "package api owners"
expect_body 'Version { version: "0.1.0", yanked: false, yank_message: none, removed: none, deps: \[\], meta: { description: "Shapes", license: "MIT", authors: \["Ann <ann@example.org>"\], keywords: \["geometry"\], categories: \["mathematics"\], metadata: { docs: { all: true } } }, has_readme: false, archive: Archive { sha256: "[0-9a-f]\{64\}", size: [0-9]*, url: "https://packages.test/api/v1/packages/geom/0.1.0/download" }, downloads: 0, recent_downloads: 0, published_by: Actor { id: 1001, login: "alice", at: [0-9]*' "package api version"
expect_body 'Version { version: "0.1.2", yanked: false, yank_message: none, removed: none, deps: \[{ name: "shapes", req: "^0.1", kind: "normal", package: "ge-om", target: "cfg(unix)" }\], meta: { description: "Shapes", categories: \["mathematics"\], has_lib: true, bin_names: \["geom-cli"\], size: 4096, future_key: { a: 1 } }, has_readme: true, archive: Archive {' "package api new fields"
expect_body 'yanked_by: Actor { id: 1001, login: "alice", at: [0-9]* }, unyanked_by: Actor { id: 1001, login: "alice"' "package api yank record"
req GET /api/v1/packages/geom/0.1.2/readme
expect_code 200 "readme api"
[ "$(header content-type)" = "text/markdown; charset=utf-8" ] || fail "readme type: $(header content-type)"
[ "$(cat "$T/b")" = "$(printf '# geom\n\nShapes, **fast**.')" ] || fail "readme text: $(cat "$T/b")"
req GET /api/v1/packages/geom/0.1.2/readme -H 'Accept: application/json'
expect_code 200 "readme json"
[ "$(header content-type)" = "application/json" ] || fail "readme json type: $(header content-type)"
expect_body '^{"name":"geom","version":"0.1.2","readme":"# geom\\n\\nShapes, \*\*fast\*\*.\\n"}$' "readme json body"
req GET /api/v1/packages/geom/0.1.0/readme
expect_code 404 "no readme"
# JSON on request, NABION by default; any origin may read.
req GET /api/v1/packages/geom -H 'Accept: application/json'
expect_code 200 "package json"
[ "$(header content-type)" = "application/json" ] || fail "package json type: $(header content-type)"
expect_body '^{"name":"geom","native":false,"owners":\[{"id":1001,"login":"alice"}\],.*"versions":\[{"version":"0.1.0","yanked":false,"yank_message":null,' "package json body"
[ "$(header access-control-allow-origin)" = "*" ] || fail "cors on a public read"
header vary | grep -q 'Accept' || fail "vary: $(header vary)"
req GET "/api/v1/packages/geom?format=json" -H 'Accept: application/nabion'
expect_body '^{"name":"geom"' "format=json wins"
req GET /api/v1/packages/geom -H 'Accept: text/html,*/*;q=0.8'
expect_body '^Package { name: "geom"' "nabion by default"
req GET "/api/v1/packages/geom?format=xml"
expect_code 400 "bad format"
expect_body '`format` is `json` or `nabion`' "bad format says what to send"
req GET /api/v1/packages/nope -H 'Accept: application/json'
expect_code 404 "json error"
expect_body '^{"message":"package `nope` is not in the index"}$' "json error body"
[ "$(header access-control-allow-origin)" = "*" ] || fail "cors on a public error"
req GET "/api/v1/docs?format=json"
expect_body '^\[{"name":' "docs index json"
req GET /api/v1/me "${auth[@]}"
[ -z "$(header access-control-allow-origin)" ] || fail "cors on an authenticated read"
req POST /api/v1/yank "${auth[@]}" --data 'x'
[ -z "$(header access-control-allow-origin)" ] || fail "cors on a write"
req GET "/api/health?format=json"
expect_body '^{"status":"ok","nabi":"[^"]*","packages":[0-9]*}$' "health json"
req GET /api/v1
expect_code 301 "api reference redirect"
[ "$(header location)" = "/api" ] || fail "api redirect: $(header location)"
req GET /api
expect_code 200 "api reference"
expect_body '<h1 class="t-h1">Registry API</h1>' "api reference title"
req GET /api/v1/packages/geom/0.1.2/x
expect_code 404 "unknown sub-route"
# Source archives: the published commit's tree, kept at publish.
req GET /api/v1/packages/geom/0.1.0/download
expect_code 200 "archive download"
[ "$(header content-type)" = "application/gzip" ] || fail "archive type: $(header content-type)"
tar -tzf "$T/b" | grep -qx 'geom-0.1.0/src/lib.nabi' || fail "archive paths: $(tar -tzf "$T/b" | head -3)"
[ "$(shasum -a 256 "$T/b" | cut -d' ' -f1)" = "$(grep -o 'archive: "[0-9a-f]\{64\}"' "$T/data/db.nabion" | head -1 | cut -d'"' -f2)" ] || fail "archive digest"
# Downloads: a GET sent whole counts; a HEAD, a 304 and a 404 do not.
etag=$(header etag)
code=$(curl -s -I -o /dev/null -w '%{http_code}' "$base/api/v1/packages/geom/0.1.0/download")
[ "$code" = 200 ] || fail "HEAD download: $code"
req GET /api/v1/packages/geom/0.1.0/download -H "If-None-Match: $etag"
expect_code 304 "download revalidated"
req GET /api/v1/packages/geom/9.9.9/download
expect_code 404 "no archive"
req GET /api/v1/packages/geom
expect_body 'url: "https://packages.test/api/v1/packages/geom/0.1.0/download" }, downloads: 1, recent_downloads: 1, published_by' "one download counted"
req GET /api/v1/native/zlib
expect_code 200 "native api"
expect_body 'meta: { license: "Zlib" }' "native api meta"
req GET /api/v1/packages/nope
expect_code 404 "unknown package api"
req POST /api/v1/packages/geom "${auth[@]}"
expect_code 405 "package api method"
ok "metadata api"

# Owners: users who logged in here, organisations and teams.
req POST /me/owners -H "Cookie: __Host-pkg_session=$sess" --data "csrf=$csrf&package=geom&login=acme"
expect_code 303 "add an organization owner"
req POST /me/owners -H "Cookie: __Host-pkg_session=$sess" --data "csrf=$csrf&package=geom&login=acme"
expect_code 409 "same owner twice"
req POST /me/owners -H "Cookie: __Host-pkg_session=$sess" --data "csrf=$csrf&package=geom&login=carol"
expect_code 400 "a user who never logged in"
expect_body "carol has not logged in to packages.nabi-lang.org yet" "never logged in body"
req POST /me/owners -H "Cookie: __Host-pkg_session=$sess" --data "csrf=$csrf&package=geom&login=nobody"
expect_code 400 "unknown GitHub name"
req POST /me/owners -H "Cookie: __Host-pkg_session=$sess" --data "csrf=$csrf&package=nope&login=acme"
expect_code 404 "owner of a package not in the index"
req POST /me/owners -H "Cookie: __Host-pkg_session=$sess" --data "csrf=$bob_csrf&package=geom&login=acme"
expect_code 403 "owner form with another session's csrf"
req POST /api/v1/owners "${auth[@]}" --data-binary 'Owner { package: "geom", login: "bob" }'
expect_code 200 "api invite a user owner"
expect_body 'Invited { package: "geom", login: "Bob" }' "api invite body"
req POST /api/v1/owners "${auth[@]}" --data-binary 'Owner { package: "geom", login: "bob" }'
expect_code 409 "invited twice"
req GET /api/v1/packages/geom
expect_body 'owners: \[{ id: 1001, login: "alice" }\], orgs' "an invited user owns nothing yet"
req GET /me -H "Cookie: __Host-pkg_session=$bob_sess"
expect_body 'action="/me/invites/accept"' "invitation on the invitee's page"
req POST /me/invites/accept -H "Cookie: __Host-pkg_session=$bob_sess" --data "csrf=$csrf&package=geom"
expect_code 403 "accept with another session's csrf"
req POST /me/invites/accept -H "Cookie: __Host-pkg_session=$bob_sess" --data "csrf=$bob_csrf&package=geom"
expect_code 303 "accept an invitation"
req POST /me/invites/accept -H "Cookie: __Host-pkg_session=$bob_sess" --data "csrf=$bob_csrf&package=geom"
expect_code 404 "accept twice"
req POST /api/v1/owners "${auth[@]}" --data-binary 'Owner { package: "geom", login: "acme/release" }'
expect_code 200 "api add a team owner"
req GET /api/v1/packages/geom
expect_body 'owners: \[{ id: 1001, login: "alice" }, { id: 1002, login: "Bob" }\], orgs: \[{ id: 4242, login: "acme" }, { id: 4242, login: "acme/release" }\]' "owners in the api"
req GET /me -H "Cookie: __Host-pkg_session=$sess"
expect_body '<td>geom</td><td><a class="who" href="https://github.com/orgs/acme/teams/release"><img class="av org"' "team owner listed"
req POST /api/v1/owners/remove "${auth[@]}" --data-binary 'Owner { package: "geom", login: "acme/release" }'
expect_code 200 "api remove an owner"
req POST /me/owners/remove -H "Cookie: __Host-pkg_session=$sess" --data "csrf=$csrf&package=geom&login=Bob"
expect_code 303 "remove a user owner"
req POST /me/owners/remove -H "Cookie: __Host-pkg_session=$sess" --data "csrf=$csrf&package=geom&login=Bob"
expect_code 404 "removed twice"
req GET /api/v1/packages/geom
expect_body 'owners: \[{ id: 1001, login: "alice" }\], orgs: \[{ id: 4242, login: "acme" }\]' "owners after removal"
ok "owners"

# Trusted publishing: a workflow's OIDC token (signed by the fake
# issuer) traded for a short-lived token scoped to the packages that
# trust that workflow.
now=$(date +%s)
# claims REPO WORKFLOW: what GitHub puts in a job's OIDC token
# (OWNER: the repository owner's id, default acme's).
claims() {
    printf '{"jti":"%s","sub":"repo:%s:ref:refs/tags/v1","aud":"%s","iss":"http://127.0.0.1:%s/oidc","repository":"%s","repository_owner_id":"%s","ref":"refs/tags/v1","actor":"carol","actor_id":"3003","run_id":"777","run_attempt":"1","workflow_ref":"%s/.github/workflows/%s@refs/tags/v1","job_workflow_ref":"%s/.github/workflows/%s@refs/tags/v1","iat":%s,"nbf":%s,"exp":%s}' \
        "$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')" "$1" "${AUD:-packages.test}" "$gh_port" "$1" "${OWNER:-4242}" "$1" "$2" "$1" "$2" "$now" "$now" "$((now + 300))"
}
mint() { curl -s --data-binary "$1" "http://127.0.0.1:$gh_port/_mint"; }
exchange() { req POST /api/v1/trusted-publishing/token --data-binary "TrustedPublishing { jwt: \"$1\" }"; }

req POST /me/trusted -H "Cookie: __Host-pkg_session=$sess" --data "csrf=$csrf&package=geom&repository=acme/geom&workflow=publish.yml"
expect_code 303 "add trusted publisher"
req POST /me/trusted -H "Cookie: __Host-pkg_session=$sess" --data "csrf=$csrf&package=geom&repository=acme/geom&workflow=publish.yml"
expect_code 409 "same trusted publisher twice"
req POST /me/trusted -H "Cookie: __Host-pkg_session=$sess" --data "csrf=$csrf&package=geom&repository=nobody/geom&workflow=publish.yml"
expect_code 400 "unknown repository"
expect_body "GitHub shows no public repository nobody/geom" "unknown repository body"
req POST /me/trusted -H "Cookie: __Host-pkg_session=$sess" --data "csrf=$csrf&package=geom&repository=acme/geom&workflow=../publish.yml"
expect_code 400 "bad workflow name"
req POST /me/trusted -H "Cookie: __Host-pkg_session=$bob_sess" --data "csrf=$bob_csrf&package=geom&repository=acme/evil&workflow=publish.yml"
expect_code 403 "not an owner"
expect_body "not open yet" "not an owner body"
req GET /me -H "Cookie: __Host-pkg_session=$sess"
expect_body '<td>geom</td><td>acme/geom</td><td>publish.yml</td>' "trusted publisher listed"
expect_body '<td>seeded</td><td>acme/seeded</td><td>publish.yml</td><td><span class="muted">any</span></td><td><span class="muted">server config</span>' "seeded publisher listed"
req GET /api/v1/trusted-publishers "${auth[@]}"
expect_code 200 "trusted publishers api"
expect_body 'TrustedPublisher { package: "geom", repository: "acme/geom", owner_id: 4242, workflow: "publish.yml", environment: "", id: "[0-9a-f]*", added_by: "alice"' "trusted publishers api body"
req POST /api/v1/trusted-publishers "${auth[@]}" --data-binary 'TrustedPublisher { package: "ge-om", repository: "acme/geom", workflow: "release.yml", environment: "release" }'
expect_code 200 "trusted publisher api add"
rid=$(sed -n 's/.*id: "\([0-9a-f]*\)".*/\1/p' "$T/b")
req POST /api/v1/trusted-publishers/remove "${auth[@]}" --data-binary "Remove { id: \"$rid\" }"
expect_code 200 "trusted publisher api remove"
req POST /api/v1/trusted-publishers/remove "${auth[@]}" --data-binary "Remove { id: \"$rid\" }"
expect_code 404 "removed twice"

jwt=$(mint "$(claims acme/geom publish.yml)")
exchange "$jwt"
expect_code 200 "exchange"
expect_body 'TrustedToken { token: "pkt_[0-9a-f]\{64\}", expires: [0-9]*, packages: \["geom"\] }' "exchange body"
ttok=$(grep -o 'pkt_[0-9a-f]\{64\}' "$T/b")
grep -q "$ttok" "$T/data/db.nabion" && fail "trusted token stored in clear"
exchange "$jwt"
expect_code 401 "replayed OIDC token"
expect_body "exchanged already" "replay body"
req POST /api/v1/trusted-publishing/token --data-binary "{\"jwt\": \"$(mint "$(claims acme/geom publish.yml)")\"}"
expect_code 200 "exchange with a JSON body"
exchange "$(mint "$(AUD=evil.example claims acme/geom publish.yml)")"
expect_code 401 "audience"
expect_body 'audience=packages.test' "audience body"
exchange "$(mint "$(claims acme/geom other.yml)")"
expect_code 403 "unknown workflow"
expect_body "no package trusts acme/geom, workflow other.yml" "unknown workflow body"
exchange "$(mint "$(claims acme/geom publish.yml | sed 's/"4242"/"4243"/')")"
expect_code 403 "owner id"
exchange "${jwt%?????}AAAAA"
expect_code 401 "bad signature"
exchange "$(printf '{"alg":"none","kid":"e2e"}' | base64 | tr '+/' '-_' | tr -d '=\n').${jwt#*.}"
expect_code 401 "alg none"
exchange "$(head -c 20000 /dev/zero | tr '\0' a)"
expect_code 413 "exchange body cap"

tauth=(-H "Authorization: Bearer $ttok")
req GET /api/v1/me "${tauth[@]}"
expect_body 'Me { login: "github:acme/geom/.github/workflows/publish.yml@refs/tags/v1", publish: true }' "trusted me"
req GET /api/v1/trusted-publishers "${tauth[@]}"
expect_code 403 "trusted token manages nothing"
req GET /api/v1/me -H "Authorization: Bearer pkt_$(printf '0%.0s' $(seq 64))"
expect_code 401 "unknown trusted token"
aauth=("${auth[@]}")
auth=("${tauth[@]}")
publish "${line//0.1.0/0.0.9}" '{ description: "Shapes" }'
expect_code 200 "trusted publish"
[ "$(git -C "$T/remote.git" log -1 --format='%an <%ae>')" = "acme/geom <index@packages.nabi-lang.org>" ] || fail "trusted commit author"
publish "${line//\"geom\"/\"ge-om\"}"
expect_code 403 "trusted token scope"
req POST /api/v1/yank "${auth[@]}" --data-binary 'Yank { name: "geom", version: "0.0.9" }'
expect_code 200 "trusted yank"
req POST /api/v1/yank "${auth[@]}" --data-binary 'Yank { name: "geom", version: "0.0.9", undo: true }'
expect_code 200 "trusted unyank"
req GET /api/v1/packages/geom
expect_body 'version: "0.0.9", yanked: false, yank_message: none, removed: none, deps: \[\], meta: { description: "Shapes" }, has_readme: false, archive: Archive { sha256: "[0-9a-f]*", size: [0-9]*, url: "https://packages.test/api/v1/packages/geom/0.0.9/download" }, downloads: 0, recent_downloads: 0, published_by: Actor { id: 4242, login: "acme", at: [0-9]*, via: Via { repository: "acme/geom", workflow: "publish.yml", ref: "refs/tags/v1", run_id: "777", run_attempt: "1", owner_id: 4242 } }' "trusted publisher recorded"
expect_body 'yanked_by: Actor { id: 4242, login: "acme", at: [0-9]*, via: Via { repository: "acme/geom"' "trusted yank recorded"

# A version a maintainer wrote with `nabi publish --index-dir` has no metadata:
# publishing it again from the same tree fills it in.
srev=$(source_repo seeded lib.nabi)
stree=$(git -C "$T/src/seeded" rev-parse "HEAD^{tree}")
sline="Package { name: \"seeded\", version: \"0.2.0\", deps: [], source: Dep::git(\"https://example.invalid/seeded\", rev: \"$srev\"), tree: \"$stree\", yanked: false, nabi_version: \"0.2.0\" }"
git clone -q "$T/remote.git" "$T/seed" 2>/dev/null
mkdir -p "$T/seed/se/ed"
echo "$sline" > "$T/seed/se/ed/seeded"
git -C "$T/seed" add -A
git -C "$T/seed" -c user.name=t -c user.email=t@t commit -q -m "Publish seeded 0.2.0"
git -C "$T/seed" push -q origin HEAD 2>/dev/null
exchange "$(mint "$(claims acme/seeded publish.yml)")"
expect_code 200 "exchange for a seeded publisher"
auth=(-H "Authorization: Bearer $(grep -o 'pkt_[0-9a-f]\{64\}' "$T/b")")
before=$(git -C "$T/remote.git" rev-parse HEAD)
publish "$sline" '{ description: "Seeded", license: "MIT", readme_content: "# seeded\n" }'
expect_code 200 "fill in metadata"
expect_body 'seeded 0.2.0 was already in the index from this tree; its missing metadata is filled in' "fill in warning"
[ "$(git -C "$T/remote.git" rev-parse HEAD)" = "$before" ] || fail "fill in committed"
req GET /api/v1/packages/seeded
expect_body 'meta: { description: "Seeded", license: "MIT" }, has_readme: true, archive: Archive { sha256: "[0-9a-f]*", size: [0-9]*, url: "https://packages.test/api/v1/packages/seeded/0.2.0/download" }, downloads: 0, recent_downloads: 0, published_by: Actor' "filled in metadata"
echo '// changed' >> "$T/src/seeded/src/lib.nabi"
git -C "$T/src/seeded" -c user.name=t -c user.email=t@t commit -q -am change
srev2=$(git -C "$T/src/seeded" rev-parse HEAD)
stree2=$(git -C "$T/src/seeded" rev-parse "HEAD^{tree}")
publish "$(echo "$sline" | sed -e "s/$srev/$srev2/" -e "s/$stree/$stree2/")"
expect_code 409 "another tree"
expect_body "from another tree ($stree)" "another tree body"
publish "${line//0.1.0/0.1.2}"
expect_code 403 "seeded token scope"
auth=("${aauth[@]}")
publish "${line//0.1.0/0.0.9}"
expect_code 409 "published through the API is taken"

req GET /me -H "Cookie: __Host-pkg_session=$sess"
pid=$(sed -n 's|.*action="/me/trusted/\([0-9a-f]*\)/remove".*|\1|p' "$T/b" | head -1)
[ -n "$pid" ] || fail "no remove form"
req POST "/me/trusted/$pid/remove" -H "Cookie: __Host-pkg_session=$sess" --data "csrf=$csrf"
expect_code 303 "remove trusted publisher"
exchange "$(mint "$(claims acme/geom publish.yml)")"
expect_code 403 "removed publisher"
sid=$(grep -o 'seed-[0-9a-f]*' "$T/data/db.nabion" | head -1)
req POST "/me/trusted/$sid/remove" -H "Cookie: __Host-pkg_session=$sess" --data "csrf=$csrf"
expect_code 400 "seeded publisher stays"
ok "trusted publishing"

# A rejected push: 503, and the checkout back at the remote's state.
printf '#!/bin/sh\nexit 1\n' > "$T/remote.git/hooks/pre-receive"
chmod +x "$T/remote.git/hooks/pre-receive"
before=$(git -C "$T/remote.git" rev-parse HEAD)
publish "${line//0.1.0/0.2.0}"
expect_code 503 "push refused"
[ "$(git -C "$T/index" rev-parse HEAD)" = "$before" ] || fail "checkout not reset"
[ -z "$(git -C "$T/index" status --porcelain)" ] || fail "checkout dirty"
rm "$T/remote.git/hooks/pre-receive"
ok "push failure"

# The site follows the index.
for _ in $(seq 100); do [ -f "$T/site/public/packages/geom.html" ] && break; sleep 0.2; done
req GET /packages/geom
expect_code 200 "package page after publish"
alice_av='<img class="av" src="https://avatars.githubusercontent.com/u/1001?s=48&v=4" width="24" height="24" alt="" loading="lazy" decoding="async">'
acme_av='<img class="av org" src="https://avatars.githubusercontent.com/u/4242?s=48&v=4" width="24" height="24" alt="" loading="lazy" decoding="async">'
expect_body "<h2 class=\"t-label\" id=\"owners\">Owners</h2><ul class=\"people\"><li><a class=\"who\" href=\"https://github.com/alice\" title=\"alice\">$alice_av<span>Alice Liddell</span></a></li><li><a class=\"who\" href=\"https://github.com/acme\">$acme_av<span>acme</span></a></li></ul>" "owners on the page"
expect_body 'by <a class="who" href="https://github.com/alice" title="alice"><img class="av" src="https://avatars.githubusercontent.com/u/1001?s=32&v=4"' "publisher on the page"
expect_body 'id="published-by">Published by</h2>' "several publishers"
req GET /packages/geom -H "Cookie: __Host-pkg_session=$sess"
expect_body 'aria-label="Account menu of alice"><img class="av" src="https://avatars.githubusercontent.com/u/1001?s=40&v=4"' "header avatar on a package page"
for _ in $(seq 50); do
    req GET /packages/geom/versions
    grep -q 'via GitHub Actions' "$T/b" && break
    sleep 0.2
done
expect_body '<td class="by"><span class="via" title="acme via GitHub Actions (acme/geom, publish.yml)"><a class="who" href="https://github.com/acme"><img class="av" src="https://avatars.githubusercontent.com/u/4242?s=32&v=4" width="16" height="16" alt="" loading="lazy" decoding="async"><span>acme</span></a></span></td>' "trusted publisher on the versions page"
expect_body '<td>4.0 KiB</td><td title="[0-9,]* in the last 90 days">[0-9,]*</td><td>nabi 0.2.0 or a later 0.2.x</td>' "size, downloads and nabi_version on the versions page"
expect_body '<th scope="col">Downloads</th>' "downloads column"
req GET /packages/geom/0.0.9
expect_body '<dt>Published</dt><dd><time datetime="[0-9T:Z-]*">[0-9-]* [0-9:]* UTC</time> by <a class="who" href="https://github.com/acme"><img class="av" src="https://avatars.githubusercontent.com/u/4242?s=32&v=4" width="16" height="16" alt="" loading="lazy" decoding="async"><span>acme</span></a> via GitHub Actions (<a href="https://github.com/acme/geom">acme/geom</a>, <a href="https://github.com/acme/geom/actions/runs/777"' "trusted publisher on the version page"
req GET /packages/geom
expect_body '<dt>Category</dt><dd class="kws"><a href="/categories/mathematics">mathematics</a></dd>' "categories on the page"
expect_body '<p>Shapes, <strong>fast</strong>.</p>' "published README rendered"
req GET /packages/geom/dependencies
expect_body 'href="/packages/ge-om">ge-om</a> <span class="muted">as</span> <span class="mono">shapes</span> <span class="tag" title="only for this target">cfg(unix)</span>' "rename and target on the page"
req GET /packages/geom/0.1.0
expect_code 200 "version page"
expect_body 'rel="canonical" href="[^"]*/packages/geom/0.1.0"' "version canonical"
req GET /packages/Geom/0.1.0
expect_code 301 "name case"
[ "$(header location)" = "/packages/geom/0.1.0" ] || fail "name case location: $(header location)"
req GET /packages/gem
expect_code 404 "missing package"
expect_body "No package named gem" "missing package body"
expect_body 'href="/packages/geom"' "closest name"
req GET "/packages?q=geo&sort=name"
expect_code 200 "search"
expect_body "<title>Search: geo - " "search title"
expect_body '<option value="name" selected>' "search sort"
req GET "/packages?q=nothing-like-it"
expect_body "No packages match" "no results"
req GET "/packages?q=gemo"
expect_code 200 "typo search"
expect_body 'Showing results for <a class="fixed" href="/packages?q=geom"><q>geom</q></a>' "typo corrected"
expect_body '<b class="nm"><mark>geom</mark></b>' "typo results"
req GET /packages/geom/badge.svg
expect_code 200 "badge"
[ "$(header content-type)" = "image/svg+xml" ] || fail "badge type: $(header content-type)"
[ "$(header cache-control)" = "public, max-age=0, s-maxage=86400, stale-if-error=86400" ] || fail "badge cache: $(header cache-control)"
expect_body '<title>geom: v[0-9.]* on packages.nabi-lang.org</title>' "badge title"
req GET /packages/geom
expect_body '<dt>Badge</dt><dd class="badge"><img src="/packages/geom/badge.svg"' "badge on the page"
req GET /categories
expect_code 200 "categories"
expect_body '<a href="/categories/mathematics">Mathematics</a><span class="ct">' "category count"
req GET /categories/mathematics
expect_code 200 "category page"
expect_body 'href="/packages/geom"' "category lists the package"
req GET /categories/mathematics/
expect_code 301 "category trailing slash"
req GET /keywords
expect_code 200 "keywords"
expect_body '<h1 class="t-h2">Keywords</h1>' "keywords title"
req GET /packages/geom/0.1.0
expect_body '<a href="/packages?q=geometry">geometry</a>' "an old version's keyword searches"
grep -q '<loc>https://packages.nabi-lang.org/categories/mathematics</loc>' "$T/site/public/sitemap.xml" || fail "category in the sitemap"
# An executable alone: no Docs tab, `nabi install` in the box, a bin tag.
req GET /packages/app
expect_code 200 "executable page"
expect_body '>nabi install</button>' "install tab"
expect_body '<span class="p" aria-hidden="true">$ </span>nabi install app</code>' "install command"
grep -o 'aria-label="Package sections">.*</nav>' "$T/b" | grep -q '>Docs<' && fail "Docs tab of an executable"
grep -q 'nabi add app' "$T/b" && fail "nabi add of an executable"
expect_body '<span class="tag" title="[^"]*">not verified</span>' "source not verified"
req GET /packages/app
grep -q '>Docs <span' "$T/b" && fail "an executable has no Docs tab"
req GET "/packages?q=app"
expect_body '<span class="tag bin" title="[^"]*">bin</span>' "bin tag in the list"
ok "site rebuilt"

# Sources the server will not fetch, and commits a repository does not
# hold on a branch or tag (as GitHub serves a fork's commits through the
# parent's address).
publish "${line//example.invalid/127.0.0.1}"
expect_code 400 "ip source"
expect_body "is an IP address" "ip source body"
publish "${line//example.invalid/localhost}"
expect_code 400 "localhost source"
loose=$(cd "$T/src/geom" && echo 'pub fn g() -> i32 { 2 }' > src/loose.nabi && git add -A && git -c user.name=t -c user.email=t@t commit -q -m loose && git rev-parse HEAD)
loose_tree=$(git -C "$T/src/geom" rev-parse "HEAD^{tree}")
git -C "$T/src/geom" reset -q --hard HEAD~1
publish "$(echo "${line//0.1.0/0.5.0}" | sed -e "s/$rev/$loose/" -e "s/$tree/$loose_tree/")"
expect_code 400 "commit on no branch"
grep -q 'is on no branch or tag\|cannot fetch' "$T/b" || fail "commit on no branch body: $(cat "$T/b")"
# A source that never answers holds no lock: logins, pages and the API
# go on while its publish waits for git's time limit.
if command -v python3 >/dev/null; then
    slow_line=${line//example.invalid/slow.invalid}
    (curl -s -o "$T/slow.b" -w '%{http_code}' -X POST "${auth[@]}" --data-binary "Publish { entry: $slow_line }" "$base/api/v1/publish" > "$T/slow.code") &
    slow=$!
    sleep 1
    t0=$(date +%s)
    req GET /api/v1/me "${auth[@]}"
    expect_code 200 "api while a source hangs"
    req POST /me/tokens -H "Cookie: __Host-pkg_session=$sess" --data "csrf=$csrf&name=during"
    expect_code 200 "account form while a source hangs"
    req GET /login
    expect_code 303 "login while a source hangs"
    [ $(( $(date +%s) - t0 )) -le 3 ] || fail "requests waited on the hanging source"
    req POST /api/v1/publish "${auth[@]}" --data-binary "Publish { entry: $slow_line }"
    expect_code 409 "a second publish from the same source"
    wait "$slow"
    [ "$(cat "$T/slow.code")" = 400 ] && grep -q "cannot fetch https://slow.invalid/geom" "$T/slow.b" || fail "hanging source: $(cat "$T/slow.code") $(cat "$T/slow.b")"
fi
ok "source checks"

# Moderation: the admins lock accounts, take packages down and approve
# names, through the admin API; each change is in audit.nabion.
req GET /api/v1/admin "${auth[@]}"
expect_code 200 "moderation list"
expect_body 'Moderation { locked: \[\], removed: \[\], approved: \[\] }' "moderation list body"
req POST /api/v1/admin/lock "${auth[@]}" --data-binary 'Lock { id: 1001, reason: "x" }'
expect_code 400 "an admin is not locked"
req POST /api/v1/admin/lock "${auth[@]}" --data-binary 'Lock { id: 1002 }'
expect_code 400 "a lock needs a reason"
req POST /api/v1/admin/lock "${auth[@]}" --data-binary 'Lock { id: 1002, reason: "spam" }'
expect_code 200 "lock an account"
req GET /me -H "Cookie: __Host-pkg_session=$bob_sess"
expect_code 303 "a locked account's session ends"
req GET /login
state=$(cookie_of __Host-pkg_state)
req GET "/auth/github/callback?code=user&state=$state" -H "Cookie: __Host-pkg_state=$state"
expect_code 403 "a locked account cannot log in"
expect_body "locked this account: spam" "locked login body"
req POST /api/v1/admin/lock "${auth[@]}" --data-binary 'Lock { id: 1002, undo: true }'
expect_code 200 "unlock"
req POST /api/v1/admin/takedown "${auth[@]}" --data-binary 'Takedown { name: "ge-om", reason: "malware" }'
expect_code 200 "take a package down"
expect_body 'TakenDown { name: "ge-om", version: "", removed: true, yanked: 1 }' "takedown body"
git -C "$T/remote.git" show HEAD:ge/-o/ge-om | grep -q 'yanked: true' || fail "taken down and yanked"
req GET /api/v1/packages/ge-om
expect_code 451 "taken down api"
expect_body "taken down by the registry: malware" "taken down api body"
for _ in $(seq 100); do [ -f "$T/site/public/packages/ge-om.html" ] || break; sleep 0.1; done
req GET /packages/ge-om
expect_code 404 "taken down page"
req POST /api/v1/admin/approve "${auth[@]}" --data-binary 'Approve { name: "geometry" }'
expect_code 200 "approve a name"
req POST /api/v1/admin/takedown "${auth[@]}" --data-binary 'Takedown { name: "ge-om", undo: true }'
expect_code 200 "restore"
req GET /api/v1/packages/ge-om
expect_code 200 "restored api"
grep -q 'action: "takedown", target: "ge_om", reason: "malware"' "$T/data/audit.nabion" || fail "audit: $(cat "$T/data/audit.nabion")"
# Five moderation steps; the accounts' own changes are logged beside them.
[ "$(grep '^Audit' "$T/data/audit.nabion" | grep -cvE 'action: "(login|logout|token-[a-z]+|owner-[a-z]+|invite-[a-z]+|trusted-[a-z]+)"')" = 5 ] || fail "audit lines: $(cat "$T/data/audit.nabion")"
ls "$T/data/backup/" | grep -q '^db-[0-9]\{10\}\.nabion$' || fail "db snapshot"
ok "moderation"

# Official packages: a version is official when a trusted publisher in
# a repository of the nabi-lang organization (5151 here) publishes it.
# Official names are protected; the site shows the mark, ranks official
# packages first among equals and filters on them.
aauth=("${auth[@]}")
# trusted_token REPO [OWNER]: a token from that repository's workflow.
trusted_token() {
    exchange "$(mint "$(OWNER=${2:-4242} claims "$1" publish.yml)")"
    expect_code 200 "exchange for $1"
    auth=(-H "Authorization: Bearer $(grep -o 'pkt_[0-9a-f]\{64\}' "$T/b")")
}
# entry NAME VERSION: an index entry for $T/src/NAME at its HEAD.
entry() {
    echo "Package { name: \"$1\", version: \"$2\", deps: [], source: Dep::git(\"https://example.invalid/$1\", rev: \"$(git -C "$T/src/$1" rev-parse HEAD)\"), tree: \"$(git -C "$T/src/$1" rev-parse "HEAD^{tree}")\", yanked: false, nabi_version: \"0.1.0\" }"
}
source_repo units lib.nabi >/dev/null
uline=$(entry units 0.1.0)
publish "${uline//yanked: false/yanked: false, official: true}"
expect_code 400 "official sent with a publish"
expect_body '`official` is set by the registry' "official sent body"
for x in nabi-lang/units acme/linalq acme/linalg nabi-lang/linalq; do
    req POST /api/v1/trusted-publishers "${auth[@]}" --data-binary "TrustedPublisher { package: \"${x#*/}\", repository: \"$x\", workflow: \"publish.yml\" }"
    expect_code 200 "trusted publisher $x"
done
trusted_token nabi-lang/units 5151
publish "$uline" '{ description: "Units of measure" }'
expect_code 200 "publish from the organization"
[ "$(git -C "$T/remote.git" show HEAD:un/it/units | sent)" = "${uline% \}}, official: true }" ] || fail "official line: $(git -C "$T/remote.git" show HEAD:un/it/units)"
req GET /api/v1/packages/units
expect_body 'unyanked_by: none, official: true }\], official: true, downloads: 0, recent_downloads: 0 }' "official in the api"
expect_body 'published_by: Actor { id: 5151, login: "nabi-lang"' "an official version is the organization's"
sed -n '/name: "units",/,/^        Release {/p' "$T/data/db.nabion" | grep -q 'official: true' || fail "official release record"
# An admin's publish is not the organization's.
auth=("${aauth[@]}")
publish "$(entry units 0.1.1)"
expect_code 200 "admin publishes units"
git -C "$T/remote.git" show HEAD:un/it/units | tail -1 | grep -q official && fail "a version from outside the organization marked official"
git -C "$T/remote.git" show HEAD:un/it/units | head -1 | grep -q ', official: true }$' || fail "earlier version changed"
req GET /api/v1/packages/units
expect_body 'official: false }\], official: false, downloads: 0, recent_downloads: 0 }' "the latest version decides"
trusted_token nabi-lang/units 5151
publish "$(entry units 0.1.2)"
expect_code 200 "organization publishes again"
# Names: an official one is the organization's, a look-alike needs approval.
source_repo linalq lib.nabi >/dev/null
source_repo linalg lib.nabi >/dev/null
trusted_token acme/linalq
publish "$(entry linalq 0.1.0)"
expect_code 403 "look-alike of an official name"
expect_body 'too close to `linalg`, an official Nabi package' "look-alike body"
qauth=("${auth[@]}")
trusted_token acme/linalg
publish "$(entry linalg 0.1.0)"
expect_code 403 "an official name"
expect_body 'is the name of an official Nabi package' "official name body"
req POST /api/v1/admin/approve "${aauth[@]}" --data-binary 'Approve { name: "linalq" }'
expect_code 200 "approve a look-alike"
auth=("${qauth[@]}")
publish "$(entry linalq 0.1.0)"
expect_code 200 "approved look-alike"
git -C "$T/remote.git" show HEAD:li/na/linalq | grep -q official && fail "a third-party line marked official"
# Moved into the organization: its next version is official, the first keeps its line.
trusted_token nabi-lang/linalq 5151
publish "$(entry linalq 0.2.0)"
expect_code 200 "publish after the move"
[ "$(git -C "$T/remote.git" show HEAD:li/na/linalq | grep -c ', official: true }$')" = 1 ] || fail "only the moved version is official"
auth=("${aauth[@]}")
for _ in $(seq 100); do grep -q 'class="official"' "$T/site/public/packages/linalq.html" 2>/dev/null && grep -q '"t":"units",.*"o":1' "$T/site/public/search-index.json" 2>/dev/null && break; sleep 0.2; done
req GET /packages/units
expect_body '<h1>units</h1><span class="ver">0.1.2</span><span class="official" title="Published from the nabi-lang organization">' "badge on the package page"
expect_body '</svg>Official</span>' "badge has a word"
expect_body 'Official: <code class="ic">use units::..;</code> alone is enough, the first build adds it.' "use alone on an official package"
req GET /packages/geom
grep -q 'class="official"' "$T/b" && fail "badge on a third-party package"
grep -q 'alone is enough' "$T/b" && fail "use alone on a third-party package"
req GET /
expect_body 'id="official">Official packages</h2>' "official section on the home page"
expect_body 'href="/packages/units"><span class="nl"><b class="nm">units</b>' "official package on the home page"
grep -q '"t":"units",.*"o":1}' "$T/site/public/search-index.json" || fail "official in the search index"
req GET "/packages?q=official:yes"
expect_code 200 "official filter"
expect_body '<title>Official packages - ' "official filter title"
expect_body 'href="/packages/units"' "official filter lists units"
grep -q 'href="/packages/geom"\|href="/packages/shapes"' "$T/b" && fail "official filter lists others"
req GET "/packages?q=official:no"
grep -q 'href="/packages/units"' "$T/b" && fail "official:no lists units"
# `n` matches the names units and linalq alike: the official one comes first.
req POST /api/v1/yank "${aauth[@]}" --data-binary 'Yank { name: "linalq", version: "0.2.0" }'
expect_code 200 "yank the official linalq"
for _ in $(seq 100); do grep -q 'class="official"' "$T/site/public/packages/linalq.html" 2>/dev/null || break; sleep 0.2; done
req GET "/packages?q=n"
first=$(grep -o 'href="/packages/\(units\|linalq\)"' "$T/b" | head -1)
[ "$first" = 'href="/packages/units"' ] || fail "official first among equals: $first"
expect_body '<b class="nm">u<mark>n</mark>its</b><span class="official"' "badge in search results"
ok "official packages"

# Revoking a token, and logging out.
req GET /me -H "Cookie: __Host-pkg_session=$sess"
tid=$(sed -n 's|.*action="/me/tokens/\([0-9a-f]*\)/revoke".*|\1|p' "$T/b" | head -1)
[ -n "$tid" ] || fail "no revoke form"

# Removing alice from the admins takes her power at once: her token,
# her account page and the trusted publishers she added. The seeded
# publisher keeps working.
req POST /me/trusted -H "Cookie: __Host-pkg_session=$sess" --data "csrf=$csrf&package=geom&repository=acme/geom&workflow=publish.yml"
expect_code 303 "admin adds a trusted publisher"
kill "$server"; wait "$server" 2>/dev/null || true
start_server 1002
req GET /api/v1/me "${auth[@]}"
expect_code 403 "demoted token"
expect_body 'Publishing is not open yet' "demoted token body"
publish "${line//0.1.0/0.3.0}"
expect_code 403 "demoted publish"
req POST /api/v1/yank "${auth[@]}" --data-binary 'Yank { name: "geom", version: "0.1.0" }'
expect_code 403 "demoted yank"
req POST /api/v1/trusted-publishers "${auth[@]}" --data-binary 'TrustedPublisher { package: "geom", repository: "acme/geom", workflow: "other.yml" }'
expect_code 403 "demoted trusted publisher api"
req POST /me/tokens -H "Cookie: __Host-pkg_session=$sess" --data "csrf=$csrf&name=again"
expect_code 403 "demoted token create"
exchange "$(mint "$(claims acme/geom publish.yml)")"
expect_code 403 "a non-admin's trusted publisher"
exchange "$(mint "$(claims acme/seeded publish.yml)")"
expect_code 200 "seeded publisher while closed"
kill "$server"; wait "$server" 2>/dev/null || true
start_server 1001

# A token limited to other packages publishes nothing else.
req POST /api/v1/publish -H "Authorization: Bearer $one" --data-binary "Publish { entry: ${line//0.1.0/0.4.0} }"
expect_code 403 "limited token, other package"
req POST "/me/tokens/$tid/revoke" -H "Cookie: __Host-pkg_session=$sess" --data "csrf=$csrf"
expect_code 303 "revoke"
req GET /api/v1/me "${auth[@]}"
expect_code 401 "revoked token"
req POST /logout -H "Cookie: __Host-pkg_session=$sess" --data "csrf=$csrf"
expect_code 303 "logout"
req GET /me -H "Cookie: __Host-pkg_session=$sess"
expect_code 303 "logged out"
for a in login logout token-revoke owner-add trusted-add; do
    grep -q "action: \"$a\"" "$T/data/audit.nabion" || fail "audited: $a"
done
ok "revoke and logout"

grep -q "code=" "$T/server.log" && fail "OAuth code in the log"
grep -q "test-secret\|gho_" "$T/server.log" && fail "secret in the log"
grep -q "pkt_\|eyJ" "$T/server.log" && fail "trusted token or OIDC token in the log"
echo "all e2e checks passed"
