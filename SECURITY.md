# Security policy

## Reporting a vulnerability

If you believe you've found a security-relevant bug in site-bootstrap, please
do **not** open a public issue. Instead, email:

**wx@tianmind.com**

with "site-bootstrap security:" in the subject. Include:

- A description of the issue and how you found it.
- A minimal reproduction, or the commit / line that's vulnerable.
- The impact you anticipate (e.g. remote code execution, credential exposure,
  local privilege escalation).

You should get a reply within 3 business days. If you don't, please email
again — mail filters can be ruthless.

## What is in scope

- Remote code execution triggered by a malicious `site.yaml`, a malicious
  Cloudflare API response, or a malicious nginx/certbot response.
- Leakage of secrets (`CF_API_TOKEN`, SSH keys, certificate material) to
  anywhere outside the operator's own machine and their designated VPS.
- Privilege escalation on either the operator's laptop or the target server
  beyond what running the equivalent shell commands by hand would require.
- Rsync / ssh logic that would let a compromised server clobber local files
  outside the project directory.

## What is not in scope

- "The operator's VPS was compromised through an unrelated attack" — we can't
  defend against attackers who already have root on your box.
- Cloudflare API misuse when the operator intentionally provides an
  over-privileged token. The README and `doctor` both recommend a Zone:DNS:Edit
  scoped token.
- Denial of service caused by operator mistakes (e.g. invalid nginx config
  that takes nginx down). `site-bootstrap` runs `nginx -t` before reload, but
  an empty config file still means nginx has no site.

## Disclosure

We prefer coordinated disclosure: once a fix is available we'll publish a
release note + CVE if warranted. Reporters who ask will be credited.
