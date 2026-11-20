# Security policy

## Reporting a vulnerability

Please do not report security issues in public issues or pull requests.

Use GitHub's private vulnerability reporting: on this repository, open the
**Security** tab and choose **Report a vulnerability**. You can also email security@nabi-lang.org.

To report a **malicious or compromised package** in the registry, use the same
private channel; include the package name, version, and what you observed. We can
yank an affected version while it is investigated.

We will acknowledge the report, work with you on a fix, and credit you in the
advisory unless you prefer otherwise. Response times, severity tracks and
coordinated disclosure follow the organization's
[security policy](https://github.com/nabi-lang/.github/blob/main/SECURITY.md).

## Supported versions

Nabi is pre-1.0. Fixes and security fixes land on the latest 0.x series only;
move to it with `nabi toolchain update`.
