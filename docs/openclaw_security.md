# OpenClaw Security Configuration Guide

> **⚠️ Disclaimer:** This document was collaboratively created by a human and an AI bot. It covers security configurations specific to the `drewpypro/clawdbot-aws` deployment using OpenClaw with Signal and Discord channels. Always validate recommendations against your own threat model and the [official OpenClaw documentation](https://docs.openclaw.ai).

---

## Table of Contents

- [Threat Model](#threat-model)
- [Gateway Security](#gateway-security)
- [Channel Security](#channel-security)
- [Credential Management](#credential-management)
- [Execution Controls](#execution-controls)
- [Network Security](#network-security)
- [Monitoring & Auditing](#monitoring--auditing)
- [AWS-Specific Risks](#aws-specific-risks)
- [Security Checklist](#security-checklist)

---

## Threat Model

When running an AI bot with access to shell commands, messaging platforms, and cloud infrastructure, the key threats are:

| Threat | Impact | Likelihood |
|--------|--------|------------|
| **Credential theft** (API keys, tokens) | Full account compromise | Medium — if secrets leak via logs, commits, or prompt injection |
| **Prompt injection** via messages | Bot executes unintended commands | Medium — anyone who can message the bot could attempt this |
| **Runaway cloud costs** | Financial damage | High — Terraform apply without cost controls |
| **Data exfiltration** | Privacy breach | Low-Medium — bot has access to files, messages, and APIs |
| **Bot token compromise** | Impersonation, spam, malicious actions | Medium — tokens stored on disk |
| **Supply chain attack** | Code execution via compromised dependencies | Low — npm packages, GitHub Actions |

---

## Gateway Security

### Bind Mode

The gateway should bind to **loopback only** unless remote access is explicitly needed:

```bash
openclaw config get gateway.bind
# Should be: loopback
```

If you need remote access, use **Tailscale** (encrypted mesh VPN) rather than binding to LAN/public:

```bash
openclaw configure --section gateway
# Or set directly:
openclaw config set gateway.bind tailnet
```

### Authentication

Always use token-based authentication for the gateway:

```bash
openclaw config get gateway.auth
# Should be: token
```

- Use strong, random tokens (not guessable passwords)
- Rotate tokens periodically
- Never commit tokens to git

### Trusted Proxies

If running behind a reverse proxy, configure trusted proxies to prevent header spoofing:

```bash
openclaw config set gateway.trustedProxies '["127.0.0.1"]'
```

Without this, an attacker could spoof `X-Forwarded-For` headers to bypass local-client checks.

### Security Audit

Run the built-in security audit regularly:

```bash
openclaw security audit
openclaw security audit --deep
```

This checks for common misconfigurations like exposed bindings, missing auth, and overly permissive settings.

---

## Channel Security

### Discord

| Setting | Recommended | Why |
|---------|-------------|-----|
| **Bot token** | Store in env file, not config | Prevents accidental exposure |
| **Gateway Intents** | Minimal required only | Reduces data the bot receives |
| **Channel allowlist** | Restrict to specific channels | Prevents bot from responding everywhere |
| **DM pairing** | Allowlist specific users | Prevents random users from commanding the bot |

**Key risks:**
- Anyone who can DM or mention the bot in an allowed channel can interact with it
- Discord bot tokens grant full bot access — treat them like passwords
- Message content intent means the bot sees ALL messages in channels it has access to

**Mitigations:**
- Use channel allowlists to limit where the bot operates
- Configure user allowlists for DM access
- Monitor the bot's activity in Discord audit logs
- Regularly rotate the bot token via the [Developer Portal](https://discord.com/developers/applications)

### Signal (signal-cli)

| Setting | Recommended | Why |
|---------|-------------|-----|
| **Account credentials** | Store in env file (`~/.env_secrets`) | Never hardcode phone numbers or account IDs |
| **Data directory** | Restrict permissions (`chmod 700`) | Contains private encryption keys |
| **Contact allowlist** | Explicit username list | Prevents unknown contacts from commanding the bot |
| **Group access** | Allowlist specific groups | Bot should only respond in known groups |

**Key risks:**
- The `signal-cli` data directory contains private keys — if compromised, the Signal identity is compromised
- Signal messages are end-to-end encrypted, but the bot decrypts them locally — local disk access = message access
- Anyone in an allowed group can interact with the bot

**Mitigations:**
```bash
# Protect signal-cli data directory
chmod 700 ~/.local/share/signal-cli/

# Store credentials in a protected env file
chmod 600 ~/.env_secrets

# Never read env_secrets directly — only source it
source ~/.env_secrets
```

---

## Credential Management

### Secrets Inventory

For this deployment, the following secrets exist:

| Secret | Location | Purpose | Rotation |
|--------|----------|---------|----------|
| Anthropic API key | OpenClaw config | AI model access | 90 days recommended |
| Discord bot token | OpenClaw config | Discord channel | On suspicion of compromise |
| Signal account | `~/.env_secrets` | Signal messaging | N/A (tied to phone number) |
| GitHub PAT | `~/.env_secrets` | Repo operations | 90 days, or use fine-grained with expiry |
| AWS credentials | GitHub Secrets | Terraform (CI only) | 90 days, prefer OIDC |

### Best Practices

1. **Never commit secrets to git** — use `.gitignore` and pre-commit hooks
2. **Use environment files** with restricted permissions (`chmod 600`)
3. **Prefer fine-grained tokens** with minimal scope and expiration dates
4. **Rotate regularly** — set calendar reminders for token rotation
5. **Use OIDC for AWS** instead of static access keys where possible ([docs](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services))
6. **Monitor for leaks** — enable GitHub secret scanning and push protection

### Pre-Commit Secret Detection

Consider adding a pre-commit hook to catch accidental secret commits:

```bash
# .git/hooks/pre-commit
#!/bin/bash
if git diff --cached | grep -iE '(sk-ant-|ghp_|AKIA|discord.*token)'; then
  echo "ERROR: Potential secret detected in staged files!"
  exit 1
fi
```

---

## Execution Controls

OpenClaw agents can execute shell commands. This is the most powerful — and most dangerous — capability.

### Exec Approval Mode

```bash
openclaw config get tools.exec
```

Options:
- **`ask`** — Agent must ask for approval before running commands (safest)
- **`allowlist`** — Only pre-approved commands run without asking
- **`full`** — Agent can run any command (most dangerous)

**Recommendation for this deployment:** Use `allowlist` mode with a carefully curated list of safe commands. Full access should only be granted temporarily for specific tasks.

### Elevated Permissions

```bash
openclaw config get tools.elevated
# Should be: disabled (unless specifically needed)
```

Elevated permissions allow the agent to run commands with sudo/root access. **Keep this disabled** unless you have a specific, time-limited need.

### Browser Control

```bash
openclaw config get browser
```

If browser automation isn't needed, disable it to reduce attack surface.

---

## Network Security

### Firewall Configuration

For this deployment, the host should have strict outbound firewall rules:

| Destination | Port | Protocol | Purpose |
|------------|------|----------|---------|
| `api.anthropic.com` | 443 | HTTPS | AI model API |
| `discord.com` / `gateway.discord.gg` | 443 | WSS/HTTPS | Discord bot |
| `github.com` | 443 | HTTPS | Git operations |
| `registry.npmjs.org` | 443 | HTTPS | Package updates |
| Signal servers | 443 | HTTPS | Signal messaging |

**Block everything else outbound.** This limits what a compromised bot can reach.

### SSL/TLS Inspection

If running behind a corporate firewall with SSL decryption (like Palo Alto), configure the CA certificate:

```bash
export NODE_EXTRA_CA_CERTS=/path/to/ca-certificate.crt
```

Add this to the systemd unit's Environment or the user's `.bashrc`.

---

## Monitoring & Auditing

### Log Monitoring

```bash
# Gateway logs
openclaw logs --follow

# Systemd journal
journalctl -u openclaw -f

# Signal activity
# (check signal-cli receive output for unexpected messages)
```

### What to Monitor

- **Unexpected commands** — Watch for shell commands the bot shouldn't be running
- **Unusual API calls** — Spikes in token usage could indicate prompt injection
- **Failed auth attempts** — Someone trying to access the gateway
- **Message patterns** — Unusual message sources or frequencies
- **AWS costs** — Set up AWS Budgets with alerts

### Anthropic API Usage

Monitor your API usage to catch unexpected spikes:
- Check the [Anthropic Console](https://console.anthropic.com/) for usage graphs
- Set up spending limits in your Anthropic account
- OpenClaw tracks usage: `openclaw gateway usage-cost`

---

## AWS-Specific Risks

This deployment uses Terraform to manage AWS infrastructure. Key risks:

### Cost Control

| Risk | Mitigation |
|------|-----------|
| Forgotten resources running | Use `terraform destroy` with environment gates |
| Expensive instance types | Restrict allowed instance types in Terraform variables |
| EBS volumes orphaned | Implement orphan volume cleanup (see PR #7) |
| Data transfer costs | Monitor outbound transfer in AWS Cost Explorer |

**Recommended:**
- Set up [AWS Budgets](https://docs.aws.amazon.com/cost-management/latest/userguide/budgets-managing-costs.html) with email/SMS alerts
- Use AWS Free Tier eligible resources where possible
- Always `terraform destroy` when not actively testing
- Tag all resources for cost attribution

### IAM Best Practices

- Use **least-privilege IAM policies** for the Terraform user
- Prefer **OIDC federation** over static access keys for GitHub Actions ([docs](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services))
- Enable **MFA** on the AWS root account and IAM users
- Use **SCPs** (Service Control Policies) if running in an AWS Organization to prevent resource creation in unauthorized regions

### Terraform State Security

- State file is stored in an **S3-compatible bucket** with credentials in GitHub Secrets
- **Never** store state locally or commit it to git
- Enable **versioning** on the state bucket for rollback capability
- Enable **encryption at rest** on the state bucket

---

## Security Checklist

Use this checklist when setting up a new OpenClaw deployment:

### Gateway
- [ ] Gateway bound to loopback (or Tailscale)
- [ ] Token-based authentication enabled
- [ ] Strong, random gateway token
- [ ] Trusted proxies configured (if behind reverse proxy)
- [ ] `openclaw security audit` passes with no critical findings

### Channels
- [ ] Discord bot token stored in env file (not plaintext config)
- [ ] Discord channel allowlist configured
- [ ] Discord DM user allowlist configured
- [ ] Signal credentials in protected env file (`chmod 600`)
- [ ] Signal data directory protected (`chmod 700`)
- [ ] Contact/group allowlists configured for Signal

### Credentials
- [ ] All secrets in env files with restricted permissions
- [ ] No secrets committed to git (check with `git log --all -p | grep -i secret`)
- [ ] Token rotation schedule set (90 days recommended)
- [ ] Fine-grained PATs used where possible
- [ ] AWS OIDC preferred over static keys

### Execution
- [ ] Exec mode set to `allowlist` or `ask` (not `full`)
- [ ] Elevated permissions disabled
- [ ] Browser control disabled (if not needed)

### Network
- [ ] Outbound firewall restricts destinations
- [ ] SSL/TLS CA configured (if applicable)
- [ ] No unnecessary ports open inbound

### Monitoring
- [ ] Gateway logs being captured
- [ ] AWS Budget alerts configured
- [ ] Anthropic API usage monitored
- [ ] Regular `openclaw security audit` scheduled

---

## References

- [OpenClaw Documentation](https://docs.openclaw.ai)
- [OpenClaw Security Audit](https://docs.openclaw.ai/cli/security)
- [GitHub Security Best Practices](https://docs.github.com/en/code-security/getting-started/github-security-features)
- [AWS Security Best Practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html)
- [AWS OIDC for GitHub Actions](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services)
- [signal-cli Security](https://github.com/AsamK/signal-cli/wiki/Security)
- [Discord Bot Best Practices](https://discord.com/developers/docs/topics/community-resources#bots)
- [OWASP Top 10 for LLM Applications](https://owasp.org/www-project-top-10-for-large-language-model-applications/)
