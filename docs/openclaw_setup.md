# OpenClaw Setup & Operations Guide

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

1. Create a bot at [Discord Developer Portal](https://discord.com/developers/applications)
2. Get the bot token
3. Run `openclaw channels add` and select Discord
4. Provide the bot token and configure intents

### Signal Setup

Signal requires `signal-cli` installed separately:
```bash
# Install signal-cli (see https://github.com/AsamK/signal-cli)
# Then configure via openclaw
openclaw channels add    # Select Signal
```

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
