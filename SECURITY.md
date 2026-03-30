# Security Policy

## Supported Versions

MarkdownPreview is maintained on a best-effort basis. Security fixes are only
provided for the latest released version on the default branch.

| Version | Supported |
| --- | --- |
| Latest | Yes |
| Older releases | No |

## Reporting a Vulnerability

Please do not report security vulnerabilities in public GitHub issues.

Use GitHub's private vulnerability reporting or security advisory flow for this
repository so the issue can be reviewed without disclosing it publicly.

Reports should include:

- A clear description of the issue
- Steps to reproduce, proof of concept, or a minimal sample file when possible
- The affected version or commit
- Any known impact or exploitation details

You can expect an initial best-effort response within 2 weeks.

## Scope

This policy covers vulnerabilities in the MarkdownPreview application itself,
including its Swift, SwiftUI, and WKWebView integration code.

Bundled third-party web assets such as `marked`, `mermaid`, and `highlight.js`
are not patched independently in this repository. If a vulnerability originates
upstream, please still report it so the dependency version can be reviewed and
updated as needed.
