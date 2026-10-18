# Security policy

This repository builds and mirrors the container images the Agentry runner
uses. It is part of the Agentry open core, and one policy covers all of it.
**Do not open a public issue for a security vulnerability.**

Report it as described in the core's
[SECURITY.md](https://github.com/blaktron/agentry/blob/main/SECURITY.md):
email **security@secureagentry.net**, or use GitHub's private vulnerability
reporting on this repository, with what you found, how to reproduce it and
what an attacker gains. The same response targets apply: a human reads it
within 2 business days, an assessment follows within 5, high and critical
issues get a fix or mitigation within 30 days, and you are credited in the
advisory if you want to be.

Particularly interesting here:

- **Supply chain**: a published image whose content does not match the
  upstream digest or pinned source that `images.tsv` and `build/<name>/`
  name, a build that fetches something it does not pin, or a signature or
  provenance check in `scripts/` that passes when it should not.
- **Image contents**: a setuid or setgid file, a secret, a credential or a
  build-time token left in a published image layer.
- **Workflows**: a workflow in `.github/workflows/` that runs code from a
  fork's pull request with write access or secrets, or that publishes an
  image a pull request could influence.

A vulnerability in an upstream image (Alpine, Node, Python, Docker's MCP
gateway or Docker Agent, and the others in `NOTICE`) goes to that upstream
project. Tell us as well if it reaches a run, so the pin can move.
