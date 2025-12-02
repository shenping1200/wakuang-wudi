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
    # 场景1: 64位电脑 (下载官方包)
    if [[ "$ARCH" == "x86_64" ]]; then
        echo ">>> 策略: 下载官方 x64 预编译包"
        LATEST_VER=$(curl -s https://api.github.com/repos/xmrig/xmrig/releases/latest | jq -r .tag_name | sed 's/^v//')
        # 使用局域网代理下载
        wget -e use_proxy=yes -e http_proxy=192.168.1.116:10809 -e https_proxy=192.168.1.116:10809 \
             --no-check-certificate \
             -q --show-progress -O xmrig.tar.gz \
             "https://github.com/xmrig/xmrig/releases/download/v${LATEST_VER}/xmrig-${LATEST_VER}-linux-static-x64.tar.gz"
        tar -xzf xmrig.tar.gz --strip-components=1 -C "$WORK_DIR"
        rm -f xmrig.tar.gz

    # 场景2: 32位 ARM (玩客云/OneCloud) - 源码编译
    elif [[ "$ARCH" == "armv7l" ]]; then
        echo ">>> 策略: ARM32 架构，开始源码编译 (预计耗时 15 分钟)..."
        
        # 1. 安装编译工具 (增加 unzip)
        echo "   [1/4] 安装编译器..."
        sudo apt update -q
        sudo apt install -y build-essential cmake libuv1-dev libssl-dev libhwloc-dev unzip jq >/dev/null
        
        # 2. 下载源码 ZIP 包 (关键修改：用 wget 替代 git，走局域网代理)
        echo "   [2/4] 下载源码压缩包..."
        rm -rf ~/xmrig-src-zip
        
        LATEST_VER=$(curl -s -x 192.168.1.116:10809 https://api.github.com/repos/xmrig/xmrig/releases/latest | jq -r .tag_name)
        # 如果获取版本失败，默认使用 v6.21.0
        if [ -z "$LATEST_VER" ] || [ "$LATEST_VER" == "null" ]; then LATEST_VER="v6.21.0"; fi
        
        echo "        版本: $LATEST_VER"
        
        # 下载 ZIP 源码
        wget -e use_proxy=yes -e http_proxy=192.168.1.116:10809 -e https_proxy=192.168.1.116:10809 \
             --no-check-certificate \
             -O xmrig-src.zip \
             "https://github.com/xmrig/xmrig/archive/refs/tags/${LATEST_VER}.zip"

        # 解压
        unzip -q xmrig-src.zip
        mv xmrig-* ~/xmrig_src
        rm xmrig-src.zip
        
        # 3. 编译
        echo "   [3/4] 开始编译 (玩客云CPU较弱，请耐心等待)..."
        mkdir -p ~/xmrig_src/build && cd ~/xmrig_src/build
        
        cmake .. -DWITH_HWLOC=OFF -DWITH_OPENCL=OFF -DWITH_CUDA=OFF >/dev/null 
        make -j$(nproc)
        
        # 4. 部署
        echo "   [4/4] 部署文件..."
        cp xmrig "$WORK_DIR/"
        echo "✅ 编译完成！"

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
