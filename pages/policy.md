# Usage policy

> **Draft.** This text has not been reviewed by a lawyer yet. It will change before the registry opens to the public.

The registry is shared by everyone who writes Nabi. This policy says what may be published and how problems are handled.

## Names

- Names are first come, first served. A name belongs to the account that first publishes it, and to the owners it adds.
- Do not take names you do not use. A package that holds no real code (a placeholder, a name kept for later) may be removed and its name given to someone who will use it.
- Some names are reserved for the Nabi project: the toolchain's names (`nabi`, `nabic`, ...) and names that start with `nabi-`, `std-` or `core-`. The standard library's `std`, `core` and `bare` are the Nabi project's own entries.
- A new name that looks like a name already in the registry (one letter apart, or the same once `0` and `o`, `1` and `l`, `-` and `_` are folded) is refused. If yours is a real, different project, ask the admins to approve the name.
- Official packages, the ones published from the nabi-lang organization, share the same name space. Their names are protected: a name that looks like an official one is refused unless the admins approve it.

## What may not be published

- Malware, or code that does something its users would not expect: collecting data, mining, opening a backdoor.
- Code or other material you have no right to publish.
- Spam, packages made to promote something, or packages that only copy another package under a new name.
- Personal data of other people, and content that is illegal or that harasses anyone.

## Using the API

Each account and each address may make a limited number of changes a minute, and an account takes at most 10 new names a day. Do not try to get around the limits.

## Reports and takedowns

- Report a malicious package, a security problem or a broken rule to security@nabi-lang.org (see [SECURITY.md](https://github.com/nabi-lang/nabi/security/policy)). Include the package, the version and what you saw.
- Copyright and other legal notices go to the same address. Say who you are, what the material is, and why you have the right to ask.
- The admins may yank a version while they look into a report, take down a package or a version (it disappears from the site and the API answers with the reason), or lock an account (no login, no publishing).
- Each step is recorded. The owners are told why, and can answer at the same address. A takedown that turns out to be wrong is undone.
