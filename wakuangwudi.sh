#!/bin/bash
set -e # 遇到错误立即停止

echo ">>> 阶段1/3: 环境检测"
ARCH=$(uname -m)
echo "系统架构: $ARCH"
TOTAL_CORES=$(nproc)

# 准备工作目录
WORK_DIR="$HOME/xmr_optimized"
mkdir -p "$WORK_DIR"

# 定义离线安装函数
install_xmrig_local() {
    # 1. 自动查找你上传的 zip 文件 (无论是 xmrig.zip 还是 xmrig-6.21.0.zip)
    LOCAL_ZIP=$(find "$HOME" -maxdepth 1 -name "xmrig*.zip" | head -n 1)

    if [ -z "$LOCAL_ZIP" ]; then
        echo "❌ 错误：未找到 zip 源码包！"
        echo "   请确认你已经把 xmrig-6.21.0.zip 上传到了 /root/ 目录下。"
        exit 1
    fi

    echo ">>> ✅ 检测到本地源码包: $LOCAL_ZIP"
    echo ">>> 策略: ARM32 架构，开始离线编译 (预计耗时 15 分钟)..."
    
    # 2. 清理旧文件 (删除那个 0KB 的空文件)
    rm -f ~/xmrig.tar.gz
    rm -rf ~/xmrig_src
    
    # 3. 安装编译工具 (使用 apt 国内源)
    echo "   [1/3] 安装编译器..."
    sudo apt update -q
    sudo apt install -y build-essential cmake libuv1-dev libssl-dev libhwloc-dev unzip jq >/dev/null
    
    # 4. 解压源码
    echo "   [2/3] 解压源码..."
    unzip -q -o "$LOCAL_ZIP" -d "$HOME/"
    
    # 自动识别解压出来的文件夹名
    EXTRACTED_DIR=$(find "$HOME" -maxdepth 1 -type d -name "xmrig-*" | grep -v "xmr_optimized" | head -n 1)
    if [ -z "$EXTRACTED_DIR" ]; then
        echo "❌ 解压失败，未找到源码目录。"
        exit 1
    fi
    mv "$EXTRACTED_DIR" ~/xmrig_src
    
    # 5. 编译
    echo "   [3/3] 开始编译 (玩客云CPU较弱，风扇会响，请耐心等待)..."
    mkdir -p ~/xmrig_src/build && cd ~/xmrig_src/build
    
    cmake .. -DWITH_HWLOC=OFF -DWITH_OPENCL=OFF -DWITH_CUDA=OFF >/dev/null 
    make -j$(nproc)
    
    # 6. 部署
    echo "   [完成] 部署文件..."
    cp xmrig "$WORK_DIR/"
    chmod +x "$WORK_DIR/xmrig"
    echo "✅ 编译成功！"
}

# ===================== 系统准备 =====================
echo ">>> 阶段2/3: 系统依赖安装"
sudo apt update -q
sudo apt install -y numactl libjemalloc2 screen jq

# 执行离线逻辑
install_xmrig_local

# 权限处理
sudo chmod 666 /dev/cpu/*/msr 2>/dev/null || true

# ===================== 启动挖矿 =====================
echo ">>> 阶段3/3: 启动挖矿"
cd "$WORK_DIR"

# 动态获取 jemalloc 路径
JEMALLOC_PATH=$(find /usr/lib -name libjemalloc.so.2 2>/dev/null | head -n 1)
if [ -n "$JEMALLOC_PATH" ]; then
    export LD_PRELOAD=$JEMALLOC_PATH
    echo "内存优化已启用: $JEMALLOC_PATH"
fi

# 启动命令
MINER_CMD="./xmrig \
  -a rx/0 \
  -o stratum+ssl://rx.unmineable.com:443 \
  -u USDT:TNUgvmqV1gPBzPzL2CXNyRvw7V6t4WiwvT.unmineable_worker_fanwasy \
  -p x \
  --threads=$TOTAL_CORES \
  --cpu-priority=5 \
  --asm=auto \
  --donate-level=0"

if command -v screen &>/dev/null; then
  screen -S xmrig -X quit 2>/dev/null || true
  sleep 1
  screen -dmS xmrig bash -c "$MINER_CMD"
  echo "✅ 成功！挖矿进程已在 screen 会话中启动。"
  echo "👉 输入 'screen -r xmrig' 查看运行界面"
else
  nohup bash -c "$MINER_CMD" >/dev/null 2>&1 &
  echo "✅ 成功！挖矿进程已后台启动。"
fi
