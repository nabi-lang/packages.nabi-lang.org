## The package registry

**packages.nabi-lang.org** is the Nabi package registry. A package on it is one git repository with `nabi.nabion` at its root and its sources in `src/`. The registry's data is nothing more than a single git repository, the [index](https://github.com/nabi-lang/packages-index). Each version points to a commit in the package's own repository, and `nabi` fetches that commit and verifies it by tree hash. There is no server hosting source tarballs.

## Using packages

Add a dependency with `nabi add` in your project directory.

```sh
nabi add json            # range compatible with the latest version (^0.1.0)
nabi add http@^0.1       # explicit range
```

`nabi add` writes one line to `deps` in `nabi.nabion`. You can also write it by hand.

```nabion
Package {
    name: "app",
    version: "0.1.0",
    deps: {
        "json": Dep::version("^0.1.0"),
    },
}
```

The next `nabi build` / `nabi run` fetches the index, picks the highest version in range (excluding yanked ones), and pins it in `nabi.lock`. In code, refer to it by the package's name, as in `use json::Value;`.

Version requirements: `^1.2` (the default; a bare version means the same), `~1.2.3`, `=1.0.0`, `>=1.2, <2`, `1.*`, `*`.

## Publishing

Publishing adds one line to the index repository. Sources are not uploaded: the line names a commit of the package's own repository. Lines are written only by the registry, as on crates.io: the index takes no pull requests.

The package repository must have `nabi.nabion` (`name`, `version`, `nabi_version`) at its root and its sources in `src/` (a library: `src/lib.nabi`; an executable: `src/main.nabi`; or both), a clean work tree, and its commit pushed to a branch or tag of `origin` (a commit only in a fork does not count). The source is fetched from an https address on a public host, and the registry keeps an archive of it, so the version stays available if the repository goes away. Dependencies must come from the index too (`Dep::version`, no `Dep::path` / `Dep::git`). `nabi_version` is the oldest nabi the package builds with (`"0.1.3"` admits nabi 0.1.3 and the later 0.1.x); each package page shows it as "Requires", and `nabi` picks for each user the newest version their toolchain builds. Check what would be published with `nabi publish --dry-run`.

With a registry account token, `nabi login` keeps it and `nabi publish` sends the line to the registry, which adds it to the index. A package that has a trusted publisher is published from GitHub Actions instead (see [Trusted publishing](#trusted-publishing)). Publishing is not open to everyone yet: tokens and trusted publishers are for the registry's maintainers for now.

A name is at most 64 characters. The standard library's tiers `std`, `core` and `bare` are entries of the index owned by the Nabi project: they ship with the toolchain, and nothing is published under their names. Names of the toolchain (`nabi`, `nabic`, ...) are reserved, and a new name one letter away from a name in the index, or the same once look-alike characters are folded (`js0n` for `json`), is refused; the [usage policy](/policy) says how to ask for one anyway. A package's owners invite other accounts to share it on the [account page](/me); an invited account owns it once it accepts.

Packages published from the nabi-lang organization are marked Official.

A package with an executable is marked **bin** in lists and search, and its page shows `nabi install <name>` (`nabi install --bin <name>` when it has a library too). A package with only an executable has no Docs tab: it has no API to document.

A version published by mistake is not deleted but yanked: `nabi yank <name>@0.3.1` (undo with `--undo`). Projects that already pinned it in `nabi.lock` keep working.

Each version's API docs are made when it is published, from its source at that commit (read, never built or run), and stay at `/packages/<name>/<version>/docs`, one page per public module as `nabi doc` makes them (`/packages/json/0.2.0/docs/read#struct.Event`); `/packages/<name>/latest/docs` is the newest version's. A module's doc is its file's leading `//!` lines; plain `//` comments are not shown. An item re-exported from a private module with `pub use` is shown where it is re-exported. When the docs cannot be made, the version is published anyway, and its docs page says why.

The index line format is described in the [index README](https://github.com/nabi-lang/packages-index#readme).

## Trusted publishing

A GitHub Actions workflow can publish a package without any token stored in the repository. GitHub gives each job an OIDC token that says which repository, workflow and environment it runs for; the registry checks GitHub's signature on it and, when the package trusts that workflow, trades it for a publish token that lasts 30 minutes and works for that package only. It is the same scheme as crates.io's, PyPI's and npm's trusted publishing.

Set it up once per package:

1. On your [account page](/me), under **Trusted publishers**, add the package, its GitHub repository (`owner/repo`), the workflow's file name (`publish.yml`) and, if the job runs in a GitHub environment, its name. Only the package's owners can add one, and while publishing is not open yet only the registry's maintainers. A package with no owner on record (one the registry's maintainers wrote into the index directly with `nabi publish --index-dir`) gets its first trusted publisher from them.
2. Add the workflow below to the repository as `.github/workflows/publish.yml`. It runs when a `v*` tag is pushed, checks that the tag matches `version` in `nabi.nabion`, trades the job's OIDC token (audience `packages.nabi-lang.org`) for a publish token, logs in with it and publishes.

```yaml
name: Publish / Package to the registry

on:
  push:
    tags: ['v*']
  # a tag pushed before this file was in the repository
  workflow_dispatch:
    inputs:
      tag:
        description: Tag to publish, e.g. v0.3.1
        required: true

permissions:
  contents: read
  id-token: write

jobs:
  publish:
    name: Publish to packages.nabi-lang.org
    runs-on: ubuntu-24.04
    steps:
      - name: Check out the tag
        uses: actions/checkout@v5
        with:
          ref: ${{ inputs.tag || github.ref }}

      - name: Install Nabi
        run: |
          v=$(curl -fsSL https://github.com/nabi-lang/nabi/releases/latest/download/nabi-version)
          curl -fsSL https://nabi.sh | NABI_NO_MODIFY_PATH=1 sh -s -- -q --version "$v"
          echo "$HOME/.nabi/bin" >> "$GITHUB_PATH"

      - name: Check the tag, tests and publish dry run
        env:
          TAG: ${{ inputs.tag || github.ref_name }}
        run: |
          want=$(sed -n 's/^ *version: "\(.*\)",*$/\1/p' nabi.nabion | head -1)
          [ "v$want" = "$TAG" ] || { echo "tag $TAG, but nabi.nabion has version $want" >&2; exit 1; }
          nabi test
          nabi publish --dry-run

      - name: Log in to packages.nabi-lang.org with the OIDC token
        run: |
          jwt=$(curl -fsS -H "Authorization: Bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
            "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=packages.nabi-lang.org" | sed -n 's/.*"value":"\([^"]*\)".*/\1/p')
          out=$(curl -sS --fail-with-body -H 'Content-Type: application/nabion' \
            --data-binary "TrustedPublishing { jwt: \"$jwt\" }" \
            https://packages.nabi-lang.org/api/v1/trusted-publishing/token) || { echo "$out" >&2; exit 1; }
          tok=$(printf '%s' "$out" | sed -n 's/.*token: "\(pkt_[0-9a-f]*\)".*/\1/p')
          [ -n "$tok" ]
          echo "::add-mask::$tok"
          printf '%s\n' "$tok" | nabi login

      - name: Publish with nabi publish
        run: nabi publish
```

Then release with `git tag v0.3.1 && git push origin v0.3.1`. For a tag pushed before the workflow was in the repository, run it by hand from the Actions tab (or `gh workflow run publish.yml -f tag=v0.3.1`): it runs the workflow from the default branch and publishes the tag's commit. Instead of `nabi login`, the step can put the token in `NABI_REGISTRY_TOKEN` for the publish step (`echo "NABI_REGISTRY_TOKEN=$tok" >> "$GITHUB_ENV"`).

Any ref of the named workflow file may publish. Give the publisher an environment: make a GitHub environment (`release`) with required reviewers and a deployment rule for `v*` tags, set `environment: release` on the job, and name it here; the registry then refuses tokens from runs outside it. Without one, protect your `v*` tags if others can push to the repository. The version page names the workflow that published it.

A version already in the index without its metadata (one the registry's maintainers wrote directly with `nabi publish --index-dir`) gets it from the same command: `nabi publish` of the same tree fills in the description, license, README and the rest, and changes nothing else.
