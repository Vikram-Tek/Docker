```markdown
# Secret Rotation Procedure

If a secret is detected by Gitleaks or CI scanning, act immediately.

## Immediate Actions
1. Identify the exposed secret (service, account, token)
2. Revoke or rotate the secret in the provider console
3. Update applications to use the new secret from a secrets manager

## Git Remediation
- Do NOT merge the commit containing the secret
- If pushed to remote, coordinate with security to remove it from history

## Post-Rotation
1. Verify secret is revoked
2. Re-scan repository
3. Notify stakeholders
4. Record incident details

## Notes
History rewrite requires coordination and approval.
