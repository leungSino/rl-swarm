#!/usr/bin/env bash
# ============================================================
# Gensyn RL Swarm 自动启动脚本（合并版）
# 基于官方 v0.1.11，同步最新逻辑，保留用户优化
# 支持 macOS / Linux / Docker 环境
# ============================================================

set -euo pipefail

ROOT=$PWD
GENRL_TAG="0.1.11"

export IDENTITY_PATH
export GENSYN_RESET_CONFIG
export CONNECT_TO_TESTNET=true
export ORG_ID
export HF_HUB_DOWNLOAD_TIMEOUT=120
export SWARM_CONTRACT="0xFaD7C5e93f28257429569B854151A1B8DCD404c2"
export PRG_CONTRACT="0x51D4db531ae706a6eC732458825465058fA23a35"
export HUGGINGFACE_ACCESS_TOKEN="None"
export PRG_GAME=true

DEFAULT_IDENTITY_PATH="$ROOT"/swarm.pem
IDENTITY_PATH=${IDENTITY_PATH:-$DEFAULT_IDENTITY_PATH}

DOCKER=${DOCKER:-""}
GENSYN_RESET_CONFIG=${GENSYN_RESET_CONFIG:-""}
CPU_ONLY=${CPU_ONLY:-""}
ORG_ID=${ORG_ID:-""}

GREEN_TEXT="\033[32m"
BLUE_TEXT="\033[34m"
RED_TEXT="\033[31m"
RESET_TEXT="\033[0m"

echo_green() { echo -e "$GREEN_TEXT$1$RESET_TEXT"; }
echo_blue()  { echo -e "$BLUE_TEXT$1$RESET_TEXT"; }
echo_red()   { echo -e "$RED_TEXT$1$RESET_TEXT"; }

ROOT_DIR="$(cd $(dirname ${BASH_SOURCE[0]}) && pwd)"

cleanup() {
    echo_green ">> Shutting down trainer..."
    # rm -r "$ROOT_DIR/modal-login/temp-data/"*.json 2>/dev/null || true
    kill -- -$$ || true
    exit 0
}

errnotify() {
    echo_red ">> Error while running rl-swarm. Check $ROOT/logs for details."
}

trap cleanup EXIT
trap errnotify ERR

echo -e "\033[38;5;224m"
cat << "EOF"
    ██████  ██            ███████ ██     ██  █████  ██████  ███    ███
    ██   ██ ██            ██      ██     ██ ██   ██ ██   ██ ████  ████
    ██████  ██      █████ ███████ ██  █  ██ ███████ ██████  ██ ████ ██
    ██   ██ ██                 ██ ██ ███ ██ ██   ██ ██   ██ ██  ██  ██
    ██   ██ ███████       ███████  ███ ███  ██   ██ ██   ██ ██      ██

    From Gensyn
EOF

mkdir -p "$ROOT/logs"

# ============================================================
# Section 1: Modal Login
# ============================================================
if [ "$CONNECT_TO_TESTNET" = true ]; then
    USER_DATA_FILE="$ROOT/modal-login/temp-data/userData.json"

    if [ -f "$USER_DATA_FILE" ]; then
        echo_green ">> Found existing login data, skipping browser login."
        ORG_ID=$(awk 'BEGIN { FS = "\"" } !/^[ \t]*[{}]/ { print $(NF - 1); exit }' "$USER_DATA_FILE")
        echo "Your ORG_ID is set to: $ORG_ID"
    else
        echo ">> Please login to create an Ethereum Server Wallet"
        cd modal-login

        # Node.js setup
        if ! command -v node >/dev/null 2>&1; then
            echo "Node.js not found. Installing via NVM..."
            export NVM_DIR="$HOME/.nvm"
            if [ ! -d "$NVM_DIR" ]; then
                curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
            fi
            [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
            nvm install node
        fi

        # Yarn setup
        if ! command -v yarn >/dev/null 2>&1; then
            if grep -qi "ubuntu" /etc/os-release 2>/dev/null || uname -r | grep -qi "microsoft"; then
                echo "Detected Ubuntu. Installing Yarn via apt..."
                curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | sudo apt-key add -
                echo "deb https://dl.yarnpkg.com/debian/ stable main" | sudo tee /etc/apt/sources.list.d/yarn.list
                sudo apt update && sudo apt install -y yarn
            else
                echo "Installing Yarn globally with npm..."
                npm install -g --silent yarn
            fi
        fi

        ENV_FILE="$ROOT/modal-login/.env"
        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i '' "3s/.*/SWARM_CONTRACT_ADDRESS=$SWARM_CONTRACT/" "$ENV_FILE"
            sed -i '' "4s/.*/PRG_CONTRACT_ADDRESS=$PRG_CONTRACT/" "$ENV_FILE"
        else
            sed -i "3s/.*/SWARM_CONTRACT_ADDRESS=$SWARM_CONTRACT/" "$ENV_FILE"
            sed -i "4s/.*/PRG_CONTRACT_ADDRESS=$PRG_CONTRACT/" "$ENV_FILE"
        fi

        # Build frontend
        if [ -z "$DOCKER" ]; then
            yarn install --immutable
            echo "Building server..."
            yarn build >"$ROOT/logs/yarn.log" 2>&1
        fi

        yarn start >>"$ROOT/logs/yarn.log" 2>&1 &
        SERVER_PID=$!
        echo "Started server process: $SERVER_PID"
        sleep 5

        # Try open in browser
        if [ -z "$DOCKER" ]; then
            if open http://localhost:3000 2>/dev/null; then
                echo_green ">> Opened http://localhost:3000 in browser."
            else
                echo ">> Please open http://localhost:3000 manually."
            fi
        else
            echo_green ">> Please open http://localhost:3000 in host browser."
        fi

        cd ..
        echo_green ">> Waiting for modal userData.json..."
        while [ ! -f "$USER_DATA_FILE" ]; do sleep 5; done
        echo "Found userData.json."

        ORG_ID=$(awk 'BEGIN { FS = "\"" } !/^[ \t]*[{}]/ { print $(NF - 1); exit }' "$USER_DATA_FILE")
        echo "Your ORG_ID is set to: $ORG_ID"

        # Wait until API key active
        echo "Waiting for API key activation..."
        while true; do
            STATUS=$(curl -s "http://localhost:3000/api/get-api-key-status?orgId=$ORG_ID")
            if [[ "$STATUS" == "activated" ]]; then
                echo_green ">> API key activated!"
                break
            else
                echo "Waiting..."
                sleep 5
            fi
        done

        # ✅ 关闭前端服务，避免残留进程
        kill $SERVER_PID || true
    fi
fi

# ============================================================
# Section 2: Python Dependencies
# ============================================================
echo_green ">> Installing Python dependencies..."
pip install --upgrade pip
pip install gensyn-genrl==${GENRL_TAG}
pip install reasoning-gym>=0.1.20
pip install hivemind@git+https://github.com/gensyn-ai/hivemind@639c964a8019de63135a2594663b5bec8e5356dd

# ============================================================
# Section 3: Configs
# ============================================================
if [ ! -d "$ROOT/configs" ]; then
    mkdir "$ROOT/configs"
fi

if [ -f "$ROOT/configs/rg-swarm.yaml" ]; then
    if ! cmp -s "$ROOT/rgym_exp/config/rg-swarm.yaml" "$ROOT/configs/rg-swarm.yaml"; then
        if [ -z "$GENSYN_RESET_CONFIG" ]; then
            echo_green ">> Config differs. To reset, set GENSYN_RESET_CONFIG."
        else
            echo_green ">> Backing up and replacing rg-swarm.yaml."
            mv "$ROOT/configs/rg-swarm.yaml" "$ROOT/configs/rg-swarm.yaml.bak"
            cp "$ROOT/rgym_exp/config/rg-swarm.yaml" "$ROOT/configs/rg-swarm.yaml"
        fi
    fi
else
    cp "$ROOT/rgym_exp/config/rg-swarm.yaml" "$ROOT/configs/rg-swarm.yaml"
fi

if [ -n "$DOCKER" ]; then
    sudo chmod -R 0777 /home/gensyn/rl_swarm/configs
fi

# ============================================================
# Section 4: Auto Model Selection
# ============================================================
export MODEL_NAME="Gensyn/Qwen2.5-0.5B-Instruct"
echo_green ">> Using model: $MODEL_NAME"

echo_green ">> Playing PRG game: true"
echo_green ">> Setup complete. Launching swarm..."
echo_blue ">> Star us on GitHub: https://github.com/gensyn-ai/rl-swarm"

python -m rgym_exp.runner.swarm_launcher \
    --config-path "$ROOT/rgym_exp/config" \
    --config-name "rg-swarm.yaml"

wait
