# Security Policy

## Scope

`AemiMarkdown` parses untrusted Markdown byte streams. Parsing is iterative, linear-time, and bounded against pathological nesting and entity expansion. No network access is performed.

## Supported Versions

Security fixes land on `main` and the latest tagged release (when releases are published). Pin a specific tag or commit revision for reproducible builds.

## Reporting a Vulnerability

Report security issues privately via [GitHub Security Advisories](https://github.com/g-cqd/AemiMarkdown/security/advisories/new). Do not open public issues with exploit details or sensitive material. Include the commit or version, platform, and a minimal reproduction.
