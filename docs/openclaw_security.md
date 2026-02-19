# OpenClaw Security Configuration Guide

*Last updated: 2026-02-19 · Tested with OpenClaw 2026.2.15*

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
- [Recommended Architecture: Isolate Channel Agents](#recommended-architecture-isolate-channel-agents)
- [Network Security](#network-security)
- [Monitoring & Auditing](#monitoring--auditing)
- [AWS-Specific Risks](#aws-specific-risks)
- [Security Checklist](#security-checklist)
- [Known CVEs & Security History](#known-cves--security-history)

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
| **Supply chain attack** | Code execution via compromised dependencies | Medium — ClawHavoc campaign found 1,184 malicious ClawHub skills ([Koi Security](https://koisecurity.com), [Snyk](https://snyk.io)) |
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

**Rate limiting and concurrency controls:**
- `agents.defaults.maxConcurrent` limits parallel agent execution
- `agents.defaults.subagents.maxConcurrent` limits parallel sub-agents
- Set Anthropic API spending limits in the [Anthropic Console](https://console.anthropic.com)
- For semi-public deployments, consider a LiteLLM proxy for centralized rate limiting, cost controls, and audit logging

### Signal (signal-cli)

| Setting | Recommended | Why |
|---------|-------------|-----|
| **Account credentials** | Store in a protected env file | Never hardcode phone numbers or account IDs |
| **Data directory** | Restrict permissions (`chmod 700`) | Contains private encryption keys |
| **Contact allowlist** | Explicit username list | Prevents unknown contacts from commanding the bot |
| **Group access** | Allowlist specific groups | Bot should only respond in known groups |

**Key risks:**
- **End-to-end encryption terminates at the bot.** Signal provides E2E encryption between the sender and the `signal-cli` instance. Once decrypted locally, all message content is accessible to anyone with file access to the clawdbot user's home directory. This is a fundamental architectural tradeoff — the bot needs to read messages to respond, but the security guarantee of E2E encryption does not extend to the bot's storage.
- The `signal-cli` data directory contains private keys — if compromised, the Signal identity is compromised
- `signal-cli` is an **unofficial, community-maintained client** — it reverse-engineers the Signal protocol and is not endorsed or audited by the Signal Foundation. Always verify downloads with SHA256 checksums and monitor the [signal-cli GitHub](https://github.com/AsamK/signal-cli) for security disclosures.
- Anyone in an allowed group can interact with the bot

**Mitigations:**
```bash
# Protect signal-cli data directory
chmod 700 ~/.local/share/signal-cli/

# Store credentials in a protected env file
chmod 600 ~/.<your-env-file>

# Source credentials at runtime — never cat/read the file directly
source ~/.<your-env-file>
```

---

## Credential Management

### Secrets Inventory

A typical OpenClaw deployment may include the following secrets:

| Secret | Purpose | Rotation |
|--------|---------|----------|
| Anthropic API key | AI model access | Every 90 days — set a calendar reminder |
| Discord bot token | Discord channel integration | Every 90 days — regenerate in [Developer Portal](https://discord.com/developers/applications) |
| Signal account credentials | Signal messaging | Rotate on compromise only |
| GitHub PAT | Repo operations | Every 90 days — use fine-grained PATs with built-in expiry dates |
| AWS credentials | Terraform (CI only) | **Never use static keys** — migrate to [OIDC federation](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services). If you must use keys, rotate every 90 days |

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

### OpenClaw Internal Credential Files

OpenClaw stores API keys, tokens, and auth profiles in plaintext JSON under `~/.openclaw/`. Key files containing secrets:
- `openclaw.json` — gateway token, Discord bot token
- `agents/main/agent/auth-profiles.json` — Anthropic API token
- Any `.pre-hardening` or `.bak` files from before configuration changes

**Recommended file permissions:**
```bash
chmod 700 ~/.openclaw/
chmod 600 ~/.openclaw/openclaw.json
chmod 700 ~/.openclaw/credentials/ ~/.openclaw/agents/

# Delete old backup files that may contain pre-hardening secrets
rm -f ~/.openclaw/openclaw.json.pre-hardening ~/.openclaw/*.bak

# Audit for plaintext secrets
grep -rn "sk-ant\|ghp_\|token" ~/.openclaw/ --include="*.json" | head -20
```

### Token Storage Alternatives

Instead of storing API keys directly in `openclaw.json`, consider these alternatives:

**Environment variables (recommended first step):** OpenClaw reads `ANTHROPIC_API_KEY` and `DISCORD_BOT_TOKEN` from the environment. Store keys in a `chmod 600` env file and reference it from the systemd unit:
```ini
[Service]
EnvironmentFile=/home/<bot-user>/.<your-env-file>
```

**Vault integration:** If you run HashiCorp Vault, the systemd `ExecStartPre` can pull secrets from Vault and export them before the gateway starts. The token never touches the config file on disk.

**LiteLLM proxy:** [LiteLLM](https://github.com/BerriAI/litellm) can sit between OpenClaw and the model provider API. OpenClaw points at `http://localhost:4000` as its provider endpoint. LiteLLM holds the real API key and provides rate limiting, cost controls, and centralized logging.

**Anthropic Workspace scoping:** Set up an Anthropic Organization at [console.anthropic.com](https://console.anthropic.com) → Settings → Organization. Create a dedicated workspace (e.g., "clawdbot-prod") and generate a key scoped to that workspace with per-workspace spending limits. If the key leaks, the blast radius is limited to that workspace's budget.

### Session Log Secret Leakage

OpenClaw logs full conversation content to session files (`~/.openclaw/agents/main/sessions/*.jsonl`). If a secret (API key, PAT, token) is ever seen by the agent during a conversation — whether the agent used it, the user pasted it, or it appeared in command output — it gets written to the session log in plaintext.

**Mitigations:**
- Never paste secrets directly into agent conversations — use environment variables or config files instead
- Inject credentials via environment variables so the agent uses them without seeing the raw value
- Periodically scan session logs for leaked secrets: `trufflehog filesystem ~/.openclaw/agents/ --only-verified`
- Consider purging old session logs on a schedule (cron job to delete sessions older than N days)
- Restrict session directory permissions: `chmod 700 ~/.openclaw/agents/`

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

### Sandbox Mode

Sandbox mode controls whether tool execution runs on the host or in a Docker container. Check your config:

```bash
openclaw config get agents.defaults.sandbox
```

Options:
- **`off`** — Everything runs on host (dangerous)
- **`non-main`** (recommended) — Isolates channel/sub-agent sessions in Docker
- **`always`** — Maximum isolation, even your own TUI session is sandboxed

The `docker.network: "none"` setting is critical — it prevents sandboxed sessions from making outbound network calls, blocking data exfiltration even if prompt injection succeeds.

### Context Isolation (Session Scope)

OpenClaw session scoping controls whether conversations share context across channels and users:
- Discord guild channel sessions are isolated per channel (`agent:<agentId>:discord:channel:<channelId>`)
- DM sessions can share the main session (`session.dmScope=main`) or be fully isolated (`per-channel-peer`)

If DMs are enabled and share the main session, context can bleed between your TUI session and DM conversations. For defense-in-depth, consider disabling DMs (`dmPolicy: "disabled"`) or explicitly setting `session.dmScope` to `per-channel-peer`.

### Command Deny List (denyCommands)

`gateway.nodes.denyCommands` blocks specific agent commands by exact name matching. Commands like `camera.snap`, `camera.clip`, `screen.record`, `calendar.add`, `contacts.add`, `reminders.add` only apply when mobile nodes (iOS/Android) are paired via the Bridge. On a headless Linux server, these entries have no effect.

For a headless deployment, the meaningful security boundaries are:
- `tools.elevated.enabled: false` (no sudo/root)
- `commands.native: false` (no slash commands)
- `sandbox.mode` configured appropriately for your threat model
- `docker.network: "none"` on sandboxed sessions to prevent data exfiltration

---

## Recommended Architecture: Isolate Channel Agents

> **This is the single highest-impact security improvement available** for most OpenClaw deployments.

The idea is simple: route untrusted channel input (Discord, Signal, etc.) to dedicated sub-agents running in sandboxed Docker containers with no network access. Reserve the main session for direct TUI/CLI use only.

```
Main session (TUI/CLI)  ← unsandboxed, direct host access, owner-only
Discord sub-agent       ← sandboxed, docker network: none
Signal sub-agent        ← sandboxed, docker network: none
```

This ensures that even if a prompt injection succeeds via a messaging channel, the attacker is trapped in a network-isolated Docker container with no access to the host filesystem or credentials.

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

> **Note on AWS Security Groups:** AWS Security Groups provide port-based filtering (e.g., allow TCP 443 outbound) but cannot filter by FQDN/domain. The egress rules allow HTTPS to *any* destination, not just the specific endpoints listed above. For true destination-based egress allowlisting, you need an AWS Network Firewall, a proxy server, or a next-generation firewall with FQDN-based rules. Our homelab deployment benefits from Palo Alto firewall FQDN-based egress rules that AWS cannot replicate at this price point.

> **⚠️ Egress filtering is critical.** Most people lock down ingress (inbound) but leave egress (outbound) wide open. If the bot is compromised via prompt injection, unrestricted egress means the attacker can exfiltrate data to any endpoint. Egress allowlisting is one of the most effective mitigations against data exfiltration — the bot only needs to reach the specific endpoints listed above.

### SSL/TLS Inspection

If running behind a corporate firewall with SSL decryption (like Palo Alto), configure the CA certificate:

```bash
export NODE_EXTRA_CA_CERTS=/path/to/ca-certificate.crt
```

Add this to the systemd unit's Environment or the user's `.bashrc`.

### mDNS Discovery Broadcasting

OpenClaw broadcasts its presence via mDNS (`_openclaw-gw._tcp` on port 5353) for local device discovery. In full mode, the mDNS TXT records expose operational details including filesystem paths, hostname, and display name.

On a segmented network (multiple VLANs), this can leak information to adjacent segments. **Disable mDNS unless you need local device discovery:**

```bash
openclaw config set gateway.mdns.enabled false
```

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

## Known CVEs & Security History

OpenClaw has had several significant security vulnerabilities. Keeping up to date is critical.

### OpenClaw CVEs (all patched in v2026.1.29+)

| CVE / GHSA | Description | CVSS | Patched |
|------------|-------------|------|---------|
| [CVE-2026-25253](https://nvd.nist.gov/vuln/detail/CVE-2026-25253) / [GHSA-g8p2-7wf7-98mq](https://github.com/openclaw/openclaw/security/advisories/GHSA-g8p2-7wf7-98mq) | **1-Click RCE** — Control UI trusted `gatewayUrl` from query string, enabling token exfiltration via crafted link | 8.8 | v2026.1.29 |
| [CVE-2026-25157](https://nvd.nist.gov/vuln/detail/CVE-2026-25157) / [GHSA-q284-4pvr-m585](https://github.com/openclaw/openclaw/security/advisories/GHSA-q284-4pvr-m585) | OS command injection via unsanitized `sshNodeCommand` path | — | v2026.1.29 |
| [CVE-2026-24763](https://nvd.nist.gov/vuln/detail/CVE-2026-24763) / [GHSA-mc68-q9jw-2h3v](https://github.com/openclaw/openclaw/security/advisories/GHSA-mc68-q9jw-2h3v) | Command injection in Docker execution via unsafe PATH handling | 8.8 | v2026.1.29 |
| [GHSA-g55j-c2v4-pjcg](https://github.com/openclaw/openclaw/security/advisories/GHSA-g55j-c2v4-pjcg) | Unauthenticated local RCE via WebSocket `config.apply` | High | v2026.1.29 |
| [CVE-2026-25475](https://nvd.nist.gov/vuln/detail/CVE-2026-25475) / [GHSA-r8g4-86fx-92mq](https://github.com/openclaw/openclaw/security/advisories/GHSA-r8g4-86fx-92mq) | Local file inclusion via MEDIA path extraction (arbitrary file read) | 6.5 | v2026.1.30 |

> ⚠️ **Action:** Verify you are running the latest OpenClaw version. Run `openclaw --version` to check, and `openclaw update check` to see if a newer release is available. OpenClaw has published numerous security patches since v2026.1.29 — staying current is critical.

### Additional Recent Advisories

| Advisory | Description |
|----------|-------------|
| [GHSA-w2cg-vxx6-5xjg](https://github.com/advisories/GHSA-w2cg-vxx6-5xjg) | DoS via large base64 media files |
| [GHSA-jqpq-mgvm-f9r6](https://github.com/advisories/GHSA-jqpq-mgvm-f9r6) | Command hijacking via unsafe PATH handling |
| [GHSA-rv39-79c4-7459](https://github.com/advisories/GHSA-rv39-79c4-7459) | Gateway connect skips device identity checks |
| [GHSA-mr32-vwc2-5j6h](https://github.com/advisories/GHSA-mr32-vwc2-5j6h) | Browser Relay `/cdp` WebSocket missing auth |
| [GHSA-g27f-9qjv-22pm](https://github.com/advisories/GHSA-g27f-9qjv-22pm) | Log poisoning (indirect prompt injection) via WebSocket headers (patched v2026.2.13) |
| [GHSA-xc7w-v5x6-cc87](https://github.com/advisories/GHSA-xc7w-v5x6-cc87) | Webhook auth bypass behind reverse proxy |
| [CVE-2026-26324](https://nvd.nist.gov/vuln/detail/CVE-2026-26324) | SSRF guard bypass via IPv4-mapped IPv6 |

> 📌 **Notable: Log Poisoning via WebSocket Headers (GHSA-g27f-9qjv-22pm)** — This is a novel indirect prompt injection vector. An attacker crafts malicious instructions into WebSocket headers when connecting to the gateway. These get written to OpenClaw's logs. If the agent later reads its own logs (e.g., for debugging), it may execute the injected instructions. Even with the gateway bound to loopback, anyone on the local network who can reach the gateway port could attempt this. Patched in v2026.2.13 — verify you're running at least this version.

### ClawHavoc Supply Chain Campaign

In February 2026, [Koi Security disclosed](https://www.koi.ai/blog/clawhavoc-341-malicious-clawedbot-skills-found-by-the-bot-they-were-targeting) a coordinated supply chain attack on OpenClaw's ClawHub skill marketplace:

- **Initial finding:** 341 malicious skills, 335 from a single campaign
- **Expanded count:** Antiy CERT analysis found **1,184 malicious packages** linked to 12 publisher accounts
- **Attack vector:** Skills disguised as crypto wallets, YouTube utilities, and trading bots instructed users to install "prerequisites" that delivered Atomic macOS Stealer (AMOS) and Windows keyloggers
- **C2 infrastructure:** All 335 ClawHavoc skills shared a single C2 IP
- **Coverage:** [The Hacker News](https://thehackernews.com/2026/02/researchers-find-341-malicious-clawhub.html), [Snyk](https://snyk.io/articles/skill-md-shell-access/), [SC Media](https://www.scworld.com/news/openclaw-agents-targeted-with-341-malicious-clawhub-skills), [Lakera](https://www.lakera.ai/blog/the-agent-skill-ecosystem-when-ai-extensions-become-a-malware-delivery-channel)

> ⚠️ **Lesson:** Treat third-party skills like untrusted code. Review `SKILL.md` files before installing. Prefer skills from verified publishers.

### Infostealer Targeting

Infostealer malware is actively targeting OpenClaw configuration files. [Hudson Rock documented](https://thehackernews.com/2026/02/infostealer-steals-openclaw-ai-agent.html) the first in-the-wild case of an infostealer exfiltrating a victim's entire `~/.openclaw/` directory, including gateway tokens, cryptographic keys, and memory files. The malware used a broad file-grabbing routine rather than a dedicated OpenClaw module, but researchers expect purpose-built modules to follow.

Multiple security vendors have confirmed that commodity infostealers are now sweeping for OpenClaw file paths (`~/.openclaw/`, `~/.clawdbot/`, `~/.clawhub/`) alongside traditional browser and wallet targets. A compromised workstation could expose gateway tokens, API keys, and session history.

**Coverage:** [The Hacker News](https://thehackernews.com/2026/02/infostealer-steals-openclaw-ai-agent.html) · [BleepingComputer](https://www.bleepingcomputer.com/news/security/infostealer-malware-found-stealing-openclaw-secrets-for-first-time/) · [Infosecurity Magazine](https://www.infosecurity-magazine.com/news/infostealer-targets-openclaw/) · [eSecurity Planet](https://www.esecurityplanet.com/threats/infostealers-target-openclaw-ai-configuration-files/) · [CyberInsider](https://cyberinsider.com/infostealer-malware-now-targeting-openclaw-ai-environments/)

> ⚠️ **Action:** Apply strict file permissions (`chmod 600`) to `~/.openclaw/openclaw.json` and any files containing tokens. See [Credential Management](#credential-management).

### Node.js CVEs (patched in v22.22.0)

These CVEs affected Node.js versions prior to 22.22.0. If you are running an older version, update immediately.

| CVE | Description | Patched |
|-----|-------------|---------|
| [CVE-2025-59466](https://nvd.nist.gov/vuln/detail/CVE-2025-59466) | async_hooks DoS — uncatchable stack overflow crash (CVSS 7.5) ([deep-dive](https://nodejs.org/en/blog/vulnerability/january-2026-dos-mitigation-async-hooks)) | Node.js 22.22.0 ([advisory](https://nodejs.org/en/blog/vulnerability/december-2025-security-releases)) |
| [CVE-2026-21636](https://nvd.nist.gov/vuln/detail/CVE-2026-21636) | Permission model bypass via Unix Domain Socket | Node.js 22.22.0 ([advisory](https://nodejs.org/en/blog/vulnerability/december-2025-security-releases)) |

---

## References

**OpenClaw & General:**
- [OpenClaw Official Security Documentation](https://docs.openclaw.ai/gateway/security)
- [OpenClaw Security Advisories (GitHub)](https://github.com/openclaw/openclaw/security/advisories)
- [OWASP Top 10 for LLM Applications](https://owasp.org/www-project-top-10-for-large-language-model-applications/)

**CVE-2026-25253 Coverage (1-Click RCE):**
- [The Hacker News — OpenClaw Bug Enables One-Click RCE](https://thehackernews.com/2026/02/openclaw-bug-enables-one-click-remote.html)
- [Hunt.io — Hunting OpenClaw Exposures (17,500+ instances)](https://hunt.io/blog/cve-2026-25253-openclaw-ai-agent-exposure)
- [SOCRadar — CVE-2026-25253 Analysis](https://socradar.io/blog/cve-2026-25253-rce-openclaw-auth-token/)
- [RunZero — OpenClaw Vulnerability](https://www.runzero.com/blog/openclaw/)

**ClawHavoc Supply Chain Campaign:**
- [Koi Security — ClawHavoc (original research)](https://www.koi.ai/blog/clawhavoc-341-malicious-clawedbot-skills-found-by-the-bot-they-were-targeting)
- [Snyk — From SKILL.md to Shell Access](https://snyk.io/articles/skill-md-shell-access/)

**Vendor Security Reports:**
- [CrowdStrike — What Security Teams Need to Know About OpenClaw](https://www.crowdstrike.com/en-us/blog/what-security-teams-need-to-know-about-openclaw-ai-super-agent/)
- [Jamf Threat Labs — OpenClaw AI Agent Vulnerability Analysis](https://www.jamf.com/blog/openclaw-ai-agent-insider-threat-analysis/)
- [Cisco — Personal AI Agents Are a Security Nightmare](https://blogs.cisco.com/ai/personal-ai-agents-like-openclaw-are-a-security-nightmare)
- [Palo Alto Networks — Why OpenClaw May Signal the Next AI Security Crisis](https://www.paloaltonetworks.com/blog/network-security/why-moltbot-may-signal-ai-crisis/)
- [Barrack.ai — Complete OpenClaw Security Timeline](https://blog.barrack.ai/openclaw-security-vulnerabilities-2026/)

**Node.js Runtime:**
- [Node.js January 2026 Security Releases](https://nodejs.org/en/blog/vulnerability/december-2025-security-releases)
- [Endor Labs — Node.js Runtime Vulnerabilities](https://www.endorlabs.com/learn/eight-for-one-multiple-vulnerabilities-fixed-in-the-node-js-runtime)

**Infrastructure & CI/CD:**
- [GitHub Security Best Practices](https://docs.github.com/en/code-security/getting-started/github-security-features)
- [AWS Security Best Practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html)
- [AWS OIDC for GitHub Actions](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services)
- [signal-cli Security](https://github.com/AsamK/signal-cli/wiki/Security)
- [Discord Bot Best Practices](https://discord.com/developers/docs/topics/community-resources#bots)
