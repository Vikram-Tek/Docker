## 🔐 Secret Detection & Secure Coding Guidelines

To prevent accidental commits of credentials, API keys, or other sensitive data, this repository uses **Gitleaks** for secret detection.

### Local Developer Setup (Required)

All contributors **must enable pre-commit hooks** before pushing code.

#### 1. Install prerequisites

```bash
brew install gitleaks
pip install pre-commit
```

#### 2. Install git hooks

From the repository root:

```bash
pre-commit install
```

This enables automatic secret scanning on every commit.

#### 3. Manual scan (optional)

You can manually scan staged changes:

```bash
gitleaks detect --staged --config-path=.gitleaks.toml
```

### Configuration

* Gitleaks rules and allowlists are defined in `.gitleaks.toml`
* Organization-specific secret patterns **must** be added there
* Known false positives may be allowlisted **only after approval**

### CI Enforcement

Even if local hooks are skipped, **Harness STO runs Gitleaks on the full repository history** during CI.
Commits containing **CRITICAL secrets will fail the pipeline**.

### ❗ Never Commit Real Secrets

* Use placeholder values such as:

  ```
  token_TEST_000000000000000000000
  ```
* All real credentials must be stored in a secrets manager (AWS Secrets Manager, Vault, etc.)

---

If you believe a finding is a false positive:

1. Rotate the secret (if applicable)
2. Add it to the allowlist in `.gitleaks.toml`
3. Open a PR explaining the exemption
