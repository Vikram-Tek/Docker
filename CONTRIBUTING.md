# Contributing

## Pre-commit hooks (Gitleaks)

This repository uses `pre-commit` with `gitleaks` to prevent secrets from being committed.

### Install pre-commit

**macOS**
```bash
brew install pre-commit
Linux / Windows

pip install pre-commit

Enable the hook (required)

Run once per workstation:

pre-commit install

Test locally
pre-commit run --all-files

If a secret is detected

Do not commit or push

Follow the secret rotation process in SECRET_ROTATION.md

Notify the security team

Bypass hooks (emergency only)
git commit --no-verify -m "message"


Bypassing requires security approval.
