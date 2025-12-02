#!/bin/bash
set -e # 遇到错误立即停止

echo ">>> 阶段1/3: 环境检测"
ARCH=$(uname -m)
echo "系统架构: $ARCH"
TOTAL_CORES=$(nproc)

# 准备工作目录
WORK_DIR="$HOME/xmr_optimized"
mkdir -p "$WORK_DIR"

# 定义安装/编译函数
install_xmrig() {
    # 场景1: 64位电脑 (尝试走代理下载官方包)
    if [[ "$ARCH" == "x86_64" ]]; then
        echo ">>> 策略: 下载官方 x64 预编译包"
        LATEST_VER=$(curl -s https://api.github.com/repos/xmrig/xmrig/releases/latest | jq -r .tag_name | sed 's/^v//')
        # 这里也加上代理，防止下载卡住
        wget -e use_proxy=yes -e https_proxy=68.1.210.189:4145 \
             -q --show-progress -O xmrig.tar.gz \
             "https://github.com/xmrig/xmrig/releases/download/v${LATEST_VER}/xmrig-${LATEST_VER}-linux-static-x64.tar.gz"
        tar -xzf xmrig.tar.gz --strip-components=1 -C "$WORK_DIR"
        rm -f xmrig.tar.gz

    # 场景2: 32位 ARM (玩客云/OneCloud) - 源码编译
    elif [[ "$ARCH" == "armv7l" ]]; then
        echo ">>> 策略: ARM32 架构，开始源码编译 (预计耗时 10-15 分钟)..."
        
        # 1. 安装编译工具 (走国内源，速度快，不走代理)
        echo "   [1/4] 安装编译器..."
        sudo apt update -q
        sudo apt install -y git build-essential cmake libuv1-dev libssl-dev libhwloc-dev >/dev/null
        
        # 2. 下载源码 (关键修改：走 SOCKS5 代理连接官方 GitHub)
        echo "   [2/4] 克隆源码 (使用 SOCKS5 代理: 68.1.210.189:4145)..."
        rm -rf ~/xmrig_src
        
        # 使用 -c 参数临时指定 git 代理，不影响系统全局
        git clone -c http.proxy="socks5://68.1.210.189:4145" --depth 1 https://github.com/xmrig/xmrig.git ~/xmrig_src
        
        # 3. 编译
        echo "   [3/4] 开始编译 (玩客云CPU较弱，请耐心等待，风扇可能会响)..."
        mkdir -p ~/xmrig_src/build && cd ~/xmrig_src/build
        
        # 针对玩客云优化编译参数
        cmake .. -DWITH_HWLOC=OFF -DWITH_OPENCL=OFF -DWITH_CUDA=OFF >/dev/null 
        make -j$(nproc)
        
        # 4. 部署
        echo "   [4/4] 部署文件..."
        cp xmrig "$WORK_DIR/"
        echo "✅ 编译完成！"

    # 场景3: 64位 ARM (其他设备)
    elif [[ "$ARCH" == "aarch64" ]]; then
        echo ">>> 策略: ARM64 架构，编译安装..."
        sudo apt update -q
        sudo apt install -y git build-essential cmake libuv1-dev libssl-dev libhwloc-dev >/dev/null
        rm -rf ~/xmrig_src
        git clone -c http.proxy="socks5://68.1.210.189:4145" --depth 1 https://github.com/xmrig/xmrig.git ~/xmrig_src
        mkdir -p ~/xmrig_src/build && cd ~/xmrig_src/build
        cmake .. >/dev/null
        make -j$(nproc)
        cp xmrig "$WORK_DIR/"
    else
        echo "❌ 不支持的架构: $ARCH"
        exit 1
    fi
}

# ===================== 系统准备 =====================
echo ">>> 阶段2/3: 系统依赖安装"
sudo apt update -q
sudo apt install -y numactl libjemalloc2 screen jq

# 执行安装/编译
install_xmrig

# 权限处理
chmod +x "$WORK_DIR/xmrig"
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
