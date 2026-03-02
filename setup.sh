
# 1. System Install
# Check if git is missing before updating to save time on reboots
if ! command -v git &> /dev/null; then
    apt-get update && apt-get install -y git wget aria2 ffmpeg python3-pip
fi

# 2. AWS S3 setup (Always run to ensure env vars are fresh)
pip install awscli --upgrade
aws configure set aws_access_key_id "$AWS_ACCESS_KEY_ID"
aws configure set aws_secret_access_key "$AWS_SECRET_ACCESS_KEY"
aws configure set default.region "$AWS_DEFAULT_REGION"

# 3. Install ComfyUI (Only if missing)
cd /workspace
if [ ! -d "ComfyUI" ]; then
    echo "Installing ComfyUI..."
    git clone https://github.com/comfyanonymous/ComfyUI.git
    cd ComfyUI
    pip install -r requirements.txt
    pip install gguf psutil
else
    echo "ComfyUI already installed. Updating..."
    cd ComfyUI
    git pull
    pip install -r requirements.txt
fi

# Download Workflow (Overwrite existing)
aws s3 cp "aws s3 cp "s3://$S3_BUCKET_NAME/workflow.json" .

# 4. Install Custom Nodes
mkdir -p custom_nodes
cd custom_nodes

# Helper function to clone and install reqs
install_node() {
    REPO_URL=$1
    DIR_NAME=$(basename $REPO_URL .git)
    if [ ! -d "$DIR_NAME" ]; then
        git clone "$REPO_URL"
        if [ -f "$DIR_NAME/requirements.txt" ]; then
            pip install -r "$DIR_NAME/requirements.txt"
        fi
    else
        echo "Node $DIR_NAME exists. Skipping clone."
    fi
}

install_node https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git
install_node https://github.com/city96/ComfyUI-GGUF.git
install_node https://github.com/Fannovel16/ComfyUI-Frame-Interpolation.git
install_node https://github.com/pythongosssss/ComfyUI-Custom-Scripts.git
install_node https://github.com/rgthree/rgthree-comfy.git
install_node https://github.com/kijai/ComfyUI-kjnodes.git
install_node https://github.com/VraethrDalkr/ComfyUI-TripleKSampler.git
install_node https://github.com/chrisgoringe/cg-use-everywhere.git
install_node https://github.com/ShmuelRonen/ComfyUI-FreeMemory 

cd .. # Back to /workspace/ComfyUI

# 5. Create Model Directories
mkdir -p models/unet models/vae models/clip models/loras models/text_encoders

# 6. Download Models
# Using -c to continue downloads if they were interrupted or exist partially
echo "Downloading Models..."

# Wan 2.2 Unets (GGUF)
aria2c -c -x 16 -s 16 -d models/unet -o wan2.2_i2v_low_noise_14B_Q4_K_M.gguf "https://huggingface.co/bullerwins/Wan2.2-I2V-A14B-GGUF/resolve/main/wan2.2_i2v_low_noise_14B_Q4_K_M.gguf"
aria2c -c -x 16 -s 16 -d models/unet -o wan2.2_i2v_high_noise_14B_Q4_K_M.gguf "https://huggingface.co/bullerwins/Wan2.2-I2V-A14B-GGUF/resolve/main/wan2.2_i2v_high_noise_14B_Q4_K_M.gguf"

# VAE
aria2c -c -x 16 -s 16 -d models/vae -o wan_2.1_vae.safetensors "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_merged/resolve/main/wan_2.1_vae.safetensors"

# Loras (Fixed Syntax)
aria2c -c -x 16 -s 16 -d models/loras -o "wan22_innie_low_14b.safetensors" "https://huggingface.co/rahul7star/wan2.2Lora/resolve/main/wan2.2/Wan2.2%20-%20T2V%20-%20Innie%20Pussy%20-%20LOW%2014B.safetensors"
aria2c -c -x 16 -s 16 -d models/loras -o "BounceLowWan2_2.safetensors" "https://huggingface.co/rahul7star/wan2.2Lora/resolve/343e351b5f0dbc6dff6aaf7594cf7bee0b74d382/BounceLowWan2_2.safetensors"

# CLIP
aria2c -c -x 16 -s 16 -d models/text_encoders -o nsfw_wan_umt5-xxl_fp8_scaled.safetensors "https://huggingface.co/NSFW-API/NSFW-Wan-UMT5-XXL/resolve/main/nsfw_wan_umt5-xxl_fp8_scaled.safetensors"

# Lightning LoRAs
aria2c -c -x 16 -s 16 -d models/loras -o wan2.2_i2v_A14b_high_noise_lora_rank64_lightx2v_4step_1022.safetensors "https://huggingface.co/lightx2v/Wan2.2-Distill-Loras/resolve/main/wan2.2_i2v_A14b_high_noise_lora_rank64_lightx2v_4step_1022.safetensors"
aria2c -c -x 16 -s 16 -d models/loras -o wan2.2_i2v_A14b_low_noise_lora_rank64_lightx2v_4step_1022.safetensors "https://huggingface.co/lightx2v/Wan2.2-Distill-Loras/resolve/main/wan2.2_i2v_A14b_low_noise_lora_rank64_lightx2v_4step_1022.safetensors"

# 7. Tailscale Setup
if ! command -v tailscale &> /dev/null; then
    curl -fsSL https://tailscale.com/install.sh | sh
fi

mkdir -p /workspace/tailscale
# Check if tailscaled is already running to avoid "address in use" errors
if ! pgrep tailscaled > /dev/null; then
    tailscaled --state=/workspace/tailscale/tailscaled.state --tun=userspace-networking --socks5-server=localhost:1055 &
    
    echo "Waiting for tailscaled to start..."
    timeout 30s bash -c 'until [ -S /var/run/tailscale/tailscaled.sock ]; do sleep 1; done'
    
    tailscale up --authkey=$TS_AUTHKEY --hostname=vast-gpu-$(hostname)
fi

# 8. Start ComfyUI
cd /workspace/ComfyUI
# Check if Comfy is already running (reboot safety)
if ! pgrep -f "main.py" > /dev/null; then
    python3 main.py --listen 0.0.0.0 --port 11888
else
    echo "ComfyUI is already running."
fi
