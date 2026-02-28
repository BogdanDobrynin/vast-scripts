#!/bin/bash

# Install Tailscale if not present
if ! command -v tailscale &> /dev/null; then
    curl -fsSL https://tailscale.com/install.sh | sh
fi

# 3. Start tailscaled with a persistent state file in /workspace
mkdir -p /workspace/tailscale
tailscaled --state=/workspace/tailscale/tailscaled.state --tun=userspace-networking --socks5-server=localhost:1055 &

# 4. Wait for tailscaled.sock to appear
echo "Waiting for tailscaled to start..."
timeout 30s bash -c 'until [ -S /var/run/tailscale/tailscaled.sock ]; do sleep 1; done'

# 5. Authenticate
tailscale up --authkey=$TS_AUTHKEY --hostname=vast-gpu-$(hostname)
