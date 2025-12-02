#!/bin/bash
set -e

echo ">>> 阶段: 启动挖矿 (使用本地系统代理)"

# 1. 确保代理服务是活着的
if systemctl is-active --quiet sing-box; then
    echo "✅ 网络服务 (sing-box) 运行正常。"
else
    echo "⚠️ 警告：代理服务未运行，正在启动..."
    systemctl start sing-box
fi

WORK_DIR="$HOME/xmr_optimized"
mkdir -p "$WORK_DIR"
TOTAL_CORES=$(nproc)

# 2. 准备挖矿程序
# 优先找工作目录 -> 其次找编译目录 -> 最后才去编译
if [ -f "$WORK_DIR/xmrig" ]; then
    echo "   ✅ 检测到 xmrig 程序，准备启动..."
elif [ -f "$HOME/xmrig_src/build/xmrig" ]; then
    echo "   ✅ 检测到已编译文件，正在部署..."
    cp "$HOME/xmrig_src/build/xmrig" "$WORK_DIR/"
else
    echo "   ⚠️ 未找到程序，正在从本地源码重新编译..."
    # 这一步通常不会触发，因为你之前已经编译成功了
    LOCAL_ZIP=$(find "$HOME" -maxdepth 1 -name "xmrig*.zip" | head -n 1)
    if [ -z "$LOCAL_ZIP" ]; then
        echo "❌ 错误：找不到源码包，无法编译。"
        exit 1
    fi
    sudo apt update -q
    sudo apt install -y build-essential cmake libuv1-dev libssl-dev libhwloc-dev unzip jq >/dev/null
    rm -rf ~/xmrig_src
    unzip -q -o "$LOCAL_ZIP" -d "$HOME/"
    EXTRACTED_DIR=$(find "$HOME" -maxdepth 1 -type d -name "xmrig-*" | grep -v "xmr_optimized" | head -n 1)
    mv "$EXTRACTED_DIR" ~/xmrig_src
    mkdir -p ~/xmrig_src/build && cd ~/xmrig_src/build
    cmake .. -DWITH_HWLOC=OFF -DWITH_OPENCL=OFF -DWITH_CUDA=OFF >/dev/null 
    make -j$(nproc)
    cp xmrig "$WORK_DIR/"
fi
chmod +x "$WORK_DIR/xmrig"

# 3. 启动挖矿
echo ">>> 启动 XMRig..."
cd "$WORK_DIR"

# 内存优化
sudo chmod 666 /dev/cpu/*/msr 2>/dev/null || true
JEMALLOC_PATH=$(find /usr/lib -name libjemalloc.so.2 2>/dev/null | head -n 1)
if [ -n "$JEMALLOC_PATH" ]; then
    export LD_PRELOAD=$JEMALLOC_PATH
fi

# 启动命令
# 强制指定代理 127.0.0.1:10800，确保走 sing-box
MINER_CMD="./xmrig \
  -a rx/0 \
  -o stratum+ssl://rx.unmineable.com:443 \
  -u USDT:TNUgvmqV1gPBzPzL2CXNyRvw7V6t4WiwvT.unmineable_worker_fanwasy \
  -p x \
  --proxy=127.0.0.1:10800 \
  --threads=$TOTAL_CORES \
  --cpu-priority=5 \
  --donate-level=1"

if command -v screen &>/dev/null; then
    # 清理旧进程
    screen -S xmrig -X quit 2>/dev/null || true
    sleep 1
    screen -dmS xmrig bash -c "$MINER_CMD"
    echo "✅ 成功！挖矿已在 Screen 后台运行。"
    echo "   网络: 自动优选 (TUIC/VLESS/Hysteria2)"
    echo "👉 输入 'screen -r xmrig' 查看运行界面"
else
    nohup bash -c "$MINER_CMD" >/dev/null 2>&1 &
    echo "✅ 成功！挖矿已后台启动。"
fi
