## The package registry

**packages.nabi-lang.org** is the Nabi package registry. A package on it is one git repository with `nabi.nabion` at its root and its sources in `src/`. The registry's data is nothing more than a single git repository, the [index](https://github.com/nabi-lang/packages-index). Each version points to a commit in the package's own repository, and the registry keeps an archive of that commit, which `nabi` downloads and checks against the index. The line format is described in the [index README](https://github.com/nabi-lang/packages-index#readme).

The guide to using and publishing packages is in the Nabi docs. This page is the short version.

## Using packages

```sh
nabi add json            # range compatible with the latest version (^0.1.0)
nabi add http@^0.1       # explicit range
```

`nabi add` writes one line to `deps` in `nabi.nabion`; the next `nabi build` picks the highest version in range (skipping yanked ones) and pins it in `nabi.lock`. Packages marked **Official** are published from the nabi-lang organization and come with the toolchain: a program that uses one gets it added on its first run. A package marked **bin** has an executable: `nabi install <name>` installs it.

More: [the package registry](https://docs.nabi-lang.org/latest/learn/11-modules-packages#the-package-registry), in chapter 11 of the guide.

## Publishing

```sh
nabi login                # a token from your account page
nabi publish --dry-run    # print the index entry; nothing leaves your machine
nabi publish
nabi yank <name>@0.3.1    # new resolutions skip it; existing locks keep working
```

Publishing is not open to everyone yet: tokens and trusted publishers are for the registry's maintainers for now. Tokens are made on the [account page](/me), where a package's owners also invite other owners and add trusted publishers. Names are first come, first served, within the [usage policy](/policy).

More, in the guide's [Publishing Packages](https://docs.nabi-lang.org/latest/learn/packages):

- [Publishing a package](https://docs.nabi-lang.org/latest/learn/packages/01-publishing): what a package needs, `nabi login`, `nabi publish`, names and owners, the API docs the registry makes, `nabi yank`
- [Trusted publishing](https://docs.nabi-lang.org/latest/learn/packages/02-trusted-publishing): publishing from GitHub Actions with no stored token, and the workflow to copy
- [Keeping an API stable](https://docs.nabi-lang.org/latest/learn/packages/03-stable-api): `#[deprecated]`, `#[non_exhaustive]` and `#[sealed]`

## The registry API

Package info, READMEs, source archives and docs are open to anyone, in NABION or JSON, from any origin: see the [API reference](/api). Each package also has a badge of its latest version for its README, at `/packages/<name>/badge.svg`.
