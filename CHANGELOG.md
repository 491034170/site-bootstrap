# Changelog

All notable changes to `site-bootstrap` are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] — initial public release

First public, runnable release. Extracted and sanitized from a studio-internal
deployment toolchain that has shipped real production sites.

### Added
- `site-bootstrap new <name>` — interactive project scaffold with `site.yaml`.
- `site-bootstrap deploy` — one-command pipeline: Cloudflare DNS →
  build → rsync → nginx config → Let's Encrypt → verify.
- `site-bootstrap dns` — Cloudflare A-record add / list (uses API tokens,
  not the legacy global key).
- `site-bootstrap cert <domain>` — standalone certbot wrapper.
- `site-bootstrap rollback` — restore the previous deployment snapshot.
- `site-bootstrap doctor` — local + remote environment sanity check.
- `--dry-run` flag: prints every action without executing it.
- Nginx and Caddy config templates (static + reverse-proxy variants).
- Zero-dep YAML reader (`awk`-based) — no Python / Ruby required.
- Install script: `curl -fsSL ... | bash`.

### Design notes
- Everything is Bash + `ssh` + `rsync` + `jq` + `curl`. No agents, no daemons.
- State lives in two places: your `site.yaml` (in the project) and
  `/var/www/<domain>.prev` (rollback snapshot on the server). Nothing else.
- Cloudflare calls use scoped API tokens; the legacy `X-Auth-Key` flow
  from the original internal script has been removed.
