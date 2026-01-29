# 🔁 Secret Rotation Procedure

This document defines the required steps when a secret is detected by Gitleaks or any other security control.

---

## 🚨 When a Secret Is Detected

1. **Assume compromise**

   * Treat all detected secrets as exposed
   * Do NOT re-use the same value

2. **Identify scope**

   * Secret type (API key, token, password, cert)
   * Affected service(s)
   * Environment(s): dev / staging / prod

3. **Rotate immediately**

   * Generate a new secret in the appropriate system:

     * AWS Secrets Manager
     * HashiCorp Vault
     * Cloud provider console
   * Update consuming applications
   * Validate service health

4. **Revoke old secret**

   * Disable or delete the exposed credential
   * Confirm it no longer works

---

## 🛡️ Post-Rotation Cleanup

### Update Gitleaks Allowlist (if needed)

If the secret appears in historical commits and has been fully rotated:

* Add the **exact value** (or safe regex) to `.gitleaks.toml` allowlist
* Include a comment noting:

  * Rotation date
  * Ticket / incident reference

Example:

```toml
regexes = [
  '''OLD_ROTATED_TOKEN_2024'''
]
```

---

## 📣 Notification & Tracking

* Create a security incident ticket (JIRA / GitHub Issue)
* Notify:

  * Security team
  * Service owner
* Attach:

  * Harness pipeline link
  * Gitleaks finding ID
  * Rotation confirmation

---

## ✅ Verification Checklist

* [ ] New secret deployed
* [ ] Old secret revoked
* [ ] Application healthy
* [ ] Allowlist updated (if applicable)
* [ ] Incident documented

---

## ❌ Prohibited Actions

* ❌ Do NOT mark active secrets as false positives
* ❌ Do NOT suppress findings without rotation
* ❌ Do NOT store secrets in code, Dockerfiles, or `.env` files
