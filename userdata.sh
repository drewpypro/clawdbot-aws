#!/bin/bash
# =============================================================================
# Clawdbot EC2 Bootstrap Script
# Installs Node.js, npm, and OpenClaw on Debian 12
# =============================================================================
set -euo pipefail

LOG="/var/log/clawdbot-bootstrap.log"
exec > >(tee -a "$LOG") 2>&1
echo "=== Clawdbot Bootstrap Started: $(date -u) ==="

# --- System Updates ---
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get upgrade -y
apt-get install -y curl git jq unzip ca-certificates gnupg

# --- Create clawdbot user ---
if ! id -u clawdbot &>/dev/null; then
  useradd -m -s /bin/bash clawdbot
  echo "Created clawdbot user"
fi

# --- Install Node.js via nvm (as clawdbot user) ---
sudo -u clawdbot bash -c '
  export HOME=/home/clawdbot
  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
  export NVM_DIR="$HOME/.nvm"
  [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
  nvm install ${node_version}
  nvm use ${node_version}
  nvm alias default ${node_version}
  echo "Node $(node --version) installed"
  echo "npm $(npm --version) installed"
'

# --- Install OpenClaw ---
sudo -u clawdbot bash -c '
  export HOME=/home/clawdbot
  export NVM_DIR="$HOME/.nvm"
  [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
  npm install -g openclaw
  echo "OpenClaw installed: $(openclaw --version 2>/dev/null || echo "installed")"
'

# --- Create workspace ---
sudo -u clawdbot mkdir -p /home/clawdbot/.openclaw/workspace

# --- Systemd service ---
cat > /etc/systemd/system/openclaw.service << 'EOF'
[Unit]
Description=OpenClaw AI Assistant
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=clawdbot
Group=clawdbot
WorkingDirectory=/home/clawdbot/.openclaw/workspace
Environment=HOME=/home/clawdbot
ExecStartPre=/bin/bash -c 'source /home/clawdbot/.nvm/nvm.sh && nvm use default'
ExecStart=/home/clawdbot/.nvm/versions/node/v22.22.0/bin/openclaw gateway start --foreground
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable openclaw.service
# Don't start yet — needs configuration first

echo "=== Clawdbot Bootstrap Complete: $(date -u) ==="
echo "Next steps:"
echo "  1. SSH in as admin, then 'sudo su - clawdbot'"
echo "  2. Run 'openclaw init' to configure"
echo "  3. Run 'systemctl start openclaw' to start the service"
