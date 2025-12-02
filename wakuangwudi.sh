#!/bin/bash
set -e # 遇到错误立即停止

echo ">>> 阶段1/3: 环境检测"
ARCH=$(uname -m)
echo "系统架构: $ARCH"
TOTAL_CORES=$(nproc)

# 你的电脑局域网IP
PROXY_IP="192.168.1.116"
# 端口改为 10809 (根据你最新的 v2rayN 截图)
HTTP_PORT="10809"

# 准备工作目录
WORK_DIR="$HOME/xmr_optimized"
mkdir -p "$WORK_DIR"

# 定义安装/编译函数
install_xmrig() {
    # 场景: ARM32 (玩客云/OneCloud) - 源码编译
    if [[ "$ARCH" == "armv7l" ]]; then
        echo ">>> 策略: ARM32 架构，开始源码编译 (预计耗时 15 分钟)..."
        
        # 1. 安装编译工具
        echo "   [1/4] 安装编译器..."
        sudo apt update -q
        sudo apt install -y build-essential cmake libuv1-dev libssl-dev libhwloc-dev unzip jq netcat-openbsd >/dev/null
        
        # 2. 网络连通性测试
        echo "   [测试] 正在检查与代理 ($PROXY_IP:$HTTP_PORT) 的连接..."
        # 使用 nc 测试端口连通性
        if nc -z -w 3 $PROXY_IP $HTTP_PORT; then
            echo "          ✅ 成功连接到电脑代理！"
        else
            echo "          ❌ 连接被拒绝！(Connection refused)"
            echo "          请检查电脑 v2rayN 底部是否显示: 局域网 [http:10809]"
            exit 1
        fi

        # 3. 下载源码
        echo "   [2/4] 下载源码压缩包..."
        rm -rf ~/xmrig_src ~/xmrig-src.zip
        
        # 使用 wget 下载 v6.21.0
        wget -e use_proxy=yes -e http_proxy=$PROXY_IP:$HTTP_PORT -e https_proxy=$PROXY_IP:$HTTP_PORT \
             --no-check-certificate \
             -T 30 -t 3 \
             -O xmrig-src.zip \
             "https://github.com/xmrig/xmrig/archive/refs/tags/v6.21.0.zip"

        if [ ! -f "xmrig-src.zip" ]; then
            echo "❌ 下载失败！文件未生成。"
            exit 1
        fi

        # 解压
        echo "        解压源码..."
        unzip -q xmrig-src.zip
        mv xmrig-6.21.0 ~/xmrig_src
        rm xmrig-src.zip
        
        # 4. 编译
        echo "   [3/4] 开始编译 (玩客云CPU较弱，请耐心等待)..."
        mkdir -p ~/xmrig_src/build && cd ~/xmrig_src/build
        
        cmake .. -DWITH_HWLOC=OFF -DWITH_OPENCL=OFF -DWITH_CUDA=OFF >/dev/null 
        make -j$(nproc)
        
        # 5. 部署
        echo "   [4/4] 部署文件..."
        cp xmrig "$WORK_DIR/"
        echo "✅ 编译完成！"

    # 场景: 64位电脑 (x86_64)
    elif [[ "$ARCH" == "x86_64" ]]; then
        echo ">>> 策略: 下载官方 x64 预编译包"
        LATEST_VER=$(curl -s https://api.github.com/repos/xmrig/xmrig/releases/latest | jq -r .tag_name | sed 's/^v//')
        wget -e use_proxy=yes -e http_proxy=$PROXY_IP:$HTTP_PORT -e https_proxy=$PROXY_IP:$HTTP_PORT \
             --no-check-certificate \
             -q --show-progress -O xmrig.tar.gz \
             "https://github.com/xmrig/xmrig/releases/download/v${LATEST_VER}/xmrig-${LATEST_VER}-linux-static-x64.tar.gz"
        tar -xzf xmrig.tar.gz --strip-components=1 -C "$WORK_DIR"
        rm -f xmrig.tar.gz
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
