#!/bin/bash

# 1. PERSISTENCE & BOOT HOOKS
# ---------------------------
# Ensure a copy of this script exists in the persistent /workspace
cp "$0" /workspace/provisioning.sh 2>/dev/null || true
chmod +x /workspace/provisioning.sh

# Wire into the Vast.ai boot tool
BOOT_HOOK="/opt/instance-tools/bin/boot_custom.sh"
echo "/bin/bash /workspace/provisioning.sh >> /workspace/boot_debug.log 2>&1 &" > "$BOOT_HOOK"
chmod +x "$BOOT_HOOK"

# 2. CONFIGURATION
# ----------------
# Note: Using 0.0.0.0 allows local (GPU) and remote (desktop/openclaw) access.
export OLLAMA_HOST="0.0.0.0:11434"
export OLLAMA_ORIGINS="*"
# TS_AUTHKEY and OLLAMA_MODEL should be set in your Vast.ai environment variables or hardcoded here

# Installs Tailscale & Ollama if missing
if ! command -v tailscale &> /dev/null; then
    curl -fsSL https://tailscale.com/install.sh | sh
fi
if ! command -v ollama &> /dev/null; then
    curl -fsSL https://ollama.com/install.sh | sh
fi

# 2. Cleanup stale processes (Crucial for unfreezing)
pkill -9 tailscaled || true
pkill -9 ollama || true
rm -f /var/run/tailscale/tailscaled.sock
sleep 2

# 3. Start Tailscale
mkdir -p /workspace/tailscale
nohup tailscaled --state=/workspace/tailscale/tailscaled.state \
    --tun=userspace-networking \
    --socks5-server=localhost:1055 > /workspace/tailscale.log 2>&1 &
disown

# 4. Wait for Tailscale Socket
timeout 30s bash -c 'until [ -S /var/run/tailscale/tailscaled.sock ]; do sleep 1; done'

# 5. Authenticate with Tailscale
tailscale up --authkey=$TS_AUTHKEY --hostname=vast-gpu-$(hostname) --accept-dns=false

# 6. Persistent Environment for your SSH sessions
# We use single quotes to ensure the '*' is saved literally (no wildcard expansion)
sed -i '/OLLAMA_HOST/d' ~/.bashrc
sed -i '/OLLAMA_ORIGINS/d' ~/.bashrc
echo 'export OLLAMA_HOST="0.0.0.0:11434"' >> ~/.bashrc
echo 'export OLLAMA_ORIGINS="*"' >> ~/.bashrc

# 7. Start Ollama
nohup ollama serve > /workspace/ollama.log 2>&1 &
disown

# 8. Wait for API Health
until curl -s http://localhost:11434/api/version > /dev/null; do
    sleep 2
done

# 9. Load Model in Background
if [ -n "$OLLAMA_MODEL" ]; then
    nohup curl -X POST "http://localhost:11434/api/pull" -d "{\"name\": \"$OLLAMA_MODEL\"}" > /workspace/model_pull.log 2>&1 &
    disown
fi

echo "Provisioning complete."
