# OpenClaw Security Configuration Guide

*Last updated: 2026-02-18 · Tested with OpenClaw 2026.2.15*

> **⚠️ Disclaimer:** This document was collaboratively created by a human and an AI bot. It covers security configurations specific to the `drewpypro/clawdbot-aws` deployment using OpenClaw with Signal and Discord channels. Always validate recommendations against your own threat model and the [official OpenClaw documentation](https://docs.openclaw.ai).

---

## TL;DR

If you read nothing else:
1. **Never use exec `full` mode** — it gives the AI unsupervised shell access. Use `allowlist` or `ask`.
2. **Prompt injection is your #1 threat** — anyone who can message the bot could potentially manipulate it. Use channel/user allowlists.
3. **Egress filter your network** — the bot only needs to reach Discord, Signal, GitHub, and Anthropic APIs. Block everything else outbound.
4. **Rotate secrets every 90 days** — or better, use OIDC/IAM roles instead of static keys.
5. **Set AWS billing alarms at $5-10** — don't find out about runaway costs from your credit card statement.
6. **Run `openclaw security audit`** regularly — it catches common misconfigurations.

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
| **Dependency confusion** | Malicious package installed via OpenClaw/npm update | Low — unsigned updates from npm registry |

---

## Prompt Injection — The #1 Threat

Prompt injection is the most dangerous threat for any AI bot with execution capabilities. It deserves special attention beyond the threat model table above.

### What Is It?

A prompt injection attack occurs when a malicious user crafts a message designed to override the AI's instructions and make it execute unintended actions. For example:

- A Discord message that tricks the bot into running shell commands
- A carefully worded request that causes the bot to reveal secrets from environment variables
- A message in a group chat that manipulates the bot into sending data to an external endpoint

### Why It's Critical Here

This bot has:
- **Shell access** via exec tools
- **Access to secrets** (API keys, tokens in env files)
- **Network access** to GitHub, AWS, Discord, Signal
- **File system access** to the workspace and home directory

A successful prompt injection could chain these capabilities: read secrets → exfiltrate via curl → game over.

### Mitigations

1. **Exec approval mode** — Use `allowlist` or `ask` mode, never `full` (see [Execution Controls](#execution-controls))
2. **Channel allowlists** — Restrict who can message the bot (see [Channel Security](#channel-security))
3. **User allowlists** — Only accept commands from trusted users/IDs
4. **Message context awareness** — OpenClaw provides inbound metadata that distinguishes system messages from user messages; the AI should treat user-provided text as untrusted
5. **Network isolation** — Sub-agents run sandboxed with `network: none` by default
6. **Monitor for anomalies** — Watch for unexpected command execution patterns in gateway logs
7. **Least privilege** — The bot account should have minimal permissions on all platforms (GitHub, AWS, Discord)

### What You Can't Fully Prevent

No current LLM is immune to prompt injection. The mitigations above reduce the attack surface, but a sufficiently clever injection may still succeed. This is an active area of research. The best defense is defense-in-depth: even if the AI is tricked, limit what damage it can do.

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
| Anthropic API key | OpenClaw config | AI model access | Every 90 days — set a calendar reminder |
| Discord bot token | OpenClaw config | Discord channel | Every 90 days — regenerate in [Developer Portal](https://discord.com/developers/applications) |
| Signal account | `~/.env_secrets` | Signal messaging | N/A (tied to phone number) — rotate on compromise only |
| GitHub PAT | `~/.env_secrets` | Repo operations | Every 90 days — use fine-grained PATs with built-in expiry dates |
| AWS credentials | GitHub Secrets | Terraform (CI only) | **Never use static keys** — migrate to [OIDC federation](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services). If you must use keys, rotate every 90 days |

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

### Scanning Existing Git History

Pre-commit hooks only catch *new* secrets. Secrets already committed to git history are the real danger — they persist in every clone forever. Use these tools to scan your full history:

- **[git-secrets](https://github.com/awslabs/git-secrets)** — AWS tool that scans commits, messages, and merges for secrets
- **[trufflehog](https://github.com/trufflesecurity/trufflehog)** — Scans git history for high-entropy strings and known secret patterns
- **[gitleaks](https://github.com/gitleaks/gitleaks)** — Fast, configurable secret scanner with pre-commit support

```bash
# Scan full repo history with trufflehog
trufflehog git file://. --since-commit HEAD~100

# Scan with gitleaks
gitleaks detect --source . --verbose
```

If you find a leaked secret: **rotate it immediately**, then use `git filter-branch` or [BFG Repo-Cleaner](https://rtyley.github.io/bfg-repo-cleaner/) to remove it from history.

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

> **🔴 CRITICAL WARNING about `full` mode:** Setting exec to `full` gives the AI **unsupervised shell access** — it can run any command without human approval. Combined with prompt injection (a malicious message crafted to manipulate the AI), this is **game over**: an attacker could execute arbitrary commands on your host, exfiltrate data, install backdoors, or pivot to other systems. **Never use `full` mode in production.** If you must use it for development, only do so in network-isolated containers with no access to secrets or sensitive systems. Use `allowlist` or `ask` mode for any deployment with real credentials or infrastructure access.

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

> **⚠️ Egress filtering is critical.** Most people lock down ingress (inbound) but leave egress (outbound) wide open. If the bot is compromised via prompt injection, unrestricted egress means the attacker can exfiltrate data to any endpoint. Egress allowlisting is one of the most effective mitigations against data exfiltration — the bot only needs to reach the specific endpoints listed above.

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
- Set up a **billing alarm at a low threshold ($5-10)** via [CloudWatch Billing Alarms](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/monitor_estimated_charges_with_cloudwatch.html) — these trigger *before* costs accumulate, unlike budgets which alert after the fact
- Set up [AWS Budgets](https://docs.aws.amazon.com/cost-management/latest/userguide/budgets-managing-costs.html) with email/SMS alerts as a secondary safety net
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
