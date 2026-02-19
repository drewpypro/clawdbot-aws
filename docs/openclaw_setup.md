# OpenClaw Setup & Operations Guide

*Last updated: 2026-02-18 · Tested with OpenClaw 2026.2.15, Node.js v22.x, Ubuntu/Debian*

Quick reference for installing, configuring, and managing OpenClaw on an EC2 instance bootstrapped by this repo's `userdata.sh`.

---

## Table of Contents

- [Initial Setup](#initial-setup)
- [Configuration](#configuration)
- [Gateway Management](#gateway-management)
- [Channel Setup](#channel-setup)
- [Troubleshooting](#troubleshooting)
- [Updating](#updating)
- [Useful Commands](#useful-commands)

---

## Initial Setup

After the EC2 instance boots and cloud-init completes:

### 1. Verify Bootstrap

```bash
# Check cloud-init finished successfully
cloud-init status
cat /var/log/clawdbot-bootstrap.log

# Verify node & openclaw installed
sudo su - clawdbot
node --version          # should be v22.x
openclaw --version      # should print version
```

### 1b. Verify IMDSv2 Enforcement (EC2 Security)

EC2 Instance Metadata Service v1 (IMDSv1) is vulnerable to SSRF attacks. Verify your instance enforces IMDSv2:

```bash
# Check if IMDSv2 is required (HttpTokens should be "required")
curl -s http://169.254.169.254/latest/meta-data/ -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" -X PUT 2>/dev/null && echo "IMDSv2 available" || echo "IMDS not reachable"

# If HttpTokens is "optional", enforce IMDSv2 via AWS CLI:
# aws ec2 modify-instance-metadata-options --instance-id <id> --http-tokens required --http-endpoint enabled
```

### 2. Run Onboarding Wizard

The onboarding wizard handles first-time setup: credentials, workspace, daemon service, and optional channel configuration.

```bash
sudo su - clawdbot
openclaw onboard
```

**Options:**
- `--install-daemon` — Install the systemd service automatically
- `--flow quickstart` — Minimal setup (API key + go)
- `--flow advanced` — Full setup with channels, skills, etc.
- `--skip-channels` — Skip chat channel setup (configure later)
- `--skip-skills` — Skip skills installation

**Non-interactive setup** (for automation):
```bash
openclaw onboard \
  --non-interactive \
  --accept-risk \
  --auth-choice anthropic-api-key \
  --anthropic-api-key "sk-ant-..." \
  --install-daemon \
  --gateway-auth token \
  --gateway-bind loopback
```

### 3. Install Daemon Service

If you didn't use `--install-daemon` during onboarding:

```bash
openclaw gateway install
```

This creates a systemd unit file. The wizard handles PATH and environment setup correctly (unlike manual unit files).

### 4. Start the Gateway

```bash
# Via systemd (recommended for production)
openclaw gateway start

# Or foreground (useful for debugging)
openclaw gateway run --verbose
```

---

## Configuration

### Interactive Configuration

```bash
# Full configuration wizard
openclaw configure

# Configure specific sections only
openclaw configure --section model        # Change AI model
openclaw configure --section channels     # Set up chat channels
openclaw configure --section gateway      # Gateway bind/auth settings
openclaw configure --section workspace    # Workspace directory
openclaw configure --section skills       # Install/manage skills
openclaw configure --section daemon       # Daemon service settings
```

### Model Configuration

```bash
# List available models
openclaw models

# The configure wizard lets you pick model + provider
openclaw configure --section model
```

---

## Gateway Management

```bash
# Status (service + gateway probe)
openclaw gateway status

# Start / stop / restart the service
openclaw gateway start
openclaw gateway stop
openclaw gateway restart

# View logs
openclaw logs                    # Recent gateway logs
openclaw logs --follow           # Stream logs (like tail -f)

# Health check
openclaw gateway health

# Full probe (reachability + discovery + health + status)
openclaw gateway probe

# Usage and cost summary
openclaw gateway usage-cost
```

### Systemd Commands (alternative)

```bash
sudo systemctl status openclaw
sudo systemctl start openclaw
sudo systemctl stop openclaw
sudo systemctl restart openclaw
sudo journalctl -u openclaw -f          # Stream logs
sudo journalctl -u openclaw -n 100      # Last 100 lines
```

---

## Channel Setup

Channels connect OpenClaw to messaging platforms (Discord, Signal, Telegram, etc.).

```bash
# List configured channels
openclaw channels list

# Add a new channel
openclaw channels add

# Check channel status
openclaw channels status
openclaw channels status --deep    # Detailed local status

# View channel logs
openclaw channels logs

# Remove a channel
openclaw channels remove
```

### Discord Bot Setup

1. Go to the [Discord Developer Portal](https://discord.com/developers/applications) and create a new application
2. Navigate to **Bot** → **Add Bot**
3. Under **Privileged Gateway Intents**, enable:
   - **Message Content Intent** (required to read message text)
   - **Server Members Intent** (optional, for member lookups)
4. Copy the bot token
5. Generate an invite URL under **OAuth2 → URL Generator**:
   - Scopes: `bot`, `applications.commands`
   - Permissions: `Send Messages`, `Read Message History`, `Add Reactions`, `Manage Messages` (adjust as needed)
6. Invite the bot to your server using the generated URL
7. Configure in OpenClaw:
   ```bash
   openclaw channels add    # Select Discord, follow prompts for bot token
   ```

> **⚠️ Token safety:** Never paste your bot token directly into a terminal command that gets saved to shell history. Use `openclaw channels add` (which handles input securely) or inject via environment variable. If you accidentally paste a token in your terminal, clear it: `history -d $(history 1 | awk '{print $1}')` and regenerate the token in the Developer Portal immediately.

**References:**
- [Discord Developer Portal](https://discord.com/developers/applications)
- [Discord.js Guide — Setting up a bot](https://discordjs.guide/preparations/setting-up-a-bot-application.html)
- [Discord Bot Permissions Calculator](https://discordapi.com/permissions.html)
- [Discord Gateway Intents](https://discord.com/developers/docs/topics/gateway#gateway-intents)

### Signal Setup (signal-cli)

Signal requires [signal-cli](https://github.com/AsamK/signal-cli) installed separately on the host.

**1. Install dependencies:**
```bash
sudo apt install default-jre-headless
```

**2. Install signal-cli:**
```bash
# Check latest version at https://github.com/AsamK/signal-cli/releases
SIGNAL_CLI_VERSION="0.13.12"
wget "https://github.com/AsamK/signal-cli/releases/download/v${SIGNAL_CLI_VERSION}/signal-cli-${SIGNAL_CLI_VERSION}-Linux.tar.gz"

# ⚠️ Verify download integrity before installing!
# Download the SHA256 checksum and verify:
wget "https://github.com/AsamK/signal-cli/releases/download/v${SIGNAL_CLI_VERSION}/signal-cli-${SIGNAL_CLI_VERSION}-Linux.tar.gz.sha256"
sha256sum -c "signal-cli-${SIGNAL_CLI_VERSION}-Linux.tar.gz.sha256"
# Expected output: signal-cli-...-Linux.tar.gz: OK
# If verification fails, DO NOT install — re-download or investigate.

sudo tar xf "signal-cli-${SIGNAL_CLI_VERSION}-Linux.tar.gz" -C /opt
sudo ln -sf "/opt/signal-cli-${SIGNAL_CLI_VERSION}/bin/signal-cli" /usr/local/bin/signal-cli
signal-cli --version
```

**3. Register or link an account:**

Option A — Link to your phone (recommended for personal use):
```bash
signal-cli link -n "clawdbot"
# Generates a URI — scan as QR code from Signal app:
# Settings → Linked Devices → Link New Device
```

Option B — Register a new number (requires a phone number that can receive SMS/voice):
```bash
signal-cli -u +1YOURNUMBER register
signal-cli -u +1YOURNUMBER verify CODE_FROM_SMS
```

**4. Test:**
```bash
signal-cli -u +1YOURNUMBER send -m "Hello from clawdbot!" -u recipient_username
signal-cli -u +1YOURNUMBER receive
```

**5. Configure in OpenClaw:**
```bash
openclaw channels add    # Select Signal, follow prompts
```

**Security best practices:**
- Store your Signal account number in an environment file, never hardcode it
- Use usernames (`-u`) instead of phone numbers where possible
- The `signal-cli` data directory (`~/.local/share/signal-cli/`) contains private keys — protect it
- `signal-cli receive` must run periodically to fetch messages (OpenClaw cron or manual)

**References:**
- [signal-cli GitHub](https://github.com/AsamK/signal-cli)
- [signal-cli Wiki](https://github.com/AsamK/signal-cli/wiki)
- [Signal CLI man page](https://github.com/AsamK/signal-cli/blob/master/man/signal-cli.1.adoc)

---

## Troubleshooting

### Health Check & Auto-Fix

```bash
# Run diagnostics
openclaw doctor

# Auto-fix common issues
openclaw doctor --fix

# Aggressive fix (overwrites service config)
openclaw doctor --fix --force

# Non-interactive fix (CI/automation)
openclaw doctor --repair --non-interactive
```

### Common Issues

**Exit code 127 (command not found)**
The systemd service can't find the `openclaw` binary. Fix by reinstalling the daemon:
```bash
sudo su - clawdbot
openclaw gateway uninstall
openclaw gateway install
openclaw gateway start
```
Or manually add PATH to the systemd unit:
```ini
[Service]
Environment=PATH=/home/clawdbot/.nvm/versions/node/v22.22.0/bin:/usr/local/bin:/usr/bin:/bin
```

**Gateway won't start**
```bash
# Check what's happening
openclaw gateway run --verbose

# Check if port is in use
openclaw gateway status
ss -tlnp | grep 19000

# If gateway starts but immediately exits, check for port conflicts:
ss -tlnp | grep $(openclaw config get gateway.port 2>/dev/null || echo 18789)

# Force kill existing and restart
openclaw gateway start --force
```

**Channel not connecting**
```bash
openclaw channels status --deep
openclaw channels logs
openclaw doctor --fix
```

### Reset Everything

```bash
# Reset config, credentials, sessions, workspace
openclaw reset

# Then re-run onboarding
openclaw onboard
```

⚠️ **Warning:** `openclaw reset` deletes all local state. Back up your workspace first.

---

## Updating

### Update OpenClaw

```bash
sudo su - clawdbot

# Update via npm
npm update -g openclaw

# Or install specific version
npm install -g openclaw@latest

# Restart the gateway to pick up changes
openclaw gateway restart
```

### Update Node.js

```bash
sudo su - clawdbot

# Load nvm
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"

# Install new version
nvm install 22      # or specific version
nvm alias default 22

# Reinstall global packages (including openclaw)
nvm reinstall-packages <old-version>

# Reinstall daemon (path changed)
openclaw gateway uninstall
openclaw gateway install
openclaw gateway start
```

---

## Useful Commands

| Command | Description |
|---------|-------------|
| `openclaw --version` | Show version |
| `openclaw onboard` | First-time setup wizard |
| `openclaw configure` | Reconfigure settings |
| `openclaw gateway status` | Service + gateway status |
| `openclaw gateway start` | Start the gateway service |
| `openclaw gateway stop` | Stop the gateway service |
| `openclaw gateway restart` | Restart the gateway |
| `openclaw gateway run --verbose` | Run in foreground (debug) |
| `openclaw gateway probe` | Full reachability probe |
| `openclaw gateway usage-cost` | Usage and cost summary |
| `openclaw doctor` | Health diagnostics |
| `openclaw doctor --fix` | Auto-fix common issues |
| `openclaw channels list` | List chat channels |
| `openclaw channels add` | Add a channel |
| `openclaw channels status --deep` | Detailed channel status |
| `openclaw logs` | View gateway logs |
| `openclaw logs --follow` | Stream logs live |
| `openclaw sessions` | Session management |
| `openclaw memory` | Memory commands |
| `openclaw plugins` | Plugin management |
| `openclaw reset` | ⚠️ Factory reset |
| `openclaw dashboard` | Open the Control UI |

---

## References

- [OpenClaw Documentation](https://docs.openclaw.ai)
- [OpenClaw GitHub](https://github.com/openclaw/openclaw)
- [OpenClaw CLI Reference](https://docs.openclaw.ai/cli)
- [Community Discord](https://discord.com/invite/clawd)
- [ClawhHub (Skills)](https://clawhub.com)
