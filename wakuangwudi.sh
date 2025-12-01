#!/bin/bash
echo ">>> 阶段1/3: 系统资源检查"

# ===================== 自动识别架构与安装策略 =====================
ARCH=$(uname -m)
echo "检测到系统架构: $ARCH"

# 初始化变量
USE_APT_INSTALL=0
XMRIG_EXEC="./xmrig"

if [[ "$ARCH" == "x86_64" ]]; then
    echo "适配机型: PC/服务器 (x64)"
    XMRIG_ASSET="x64"
    JEMALLOC_PATH="/usr/lib/x86_64-linux-gnu/libjemalloc.so.2"
elif [[ "$ARCH" == "aarch64" ]]; then
    echo "适配机型: 树莓派/N1 (ARM64)"
    XMRIG_ASSET="arm64"
    JEMALLOC_PATH="/usr/lib/aarch64-linux-gnu/libjemalloc.so.2"
elif [[ "$ARCH" == "armv7l" ]]; then
    echo "适配机型: 玩客云/OneCloud (ARM32)"
    echo "策略: 官方源不含ARM32文件，将使用 apt 软件源安装"
    USE_APT_INSTALL=1
    XMRIG_EXEC="xmrig" # 使用系统全局命令
    JEMALLOC_PATH="/usr/lib/arm-linux-gnueabihf/libjemalloc.so.2"
else
    echo "❌ 错误：不支持的架构 $ARCH"
    exit 1
fi
# ===============================================================

# 获取核心数
TOTAL_CORES=$(nproc)
echo "总CPU核心: $TOTAL_CORES"

# 尝试启用内存优化
if [ -f "$JEMALLOC_PATH" ]; then
    export LD_PRELOAD=$JEMALLOC_PATH
    echo "已启用内存优化: $JEMALLOC_PATH"
fi

# ===================== 系统准备 =====================
echo ">>> 阶段2/3: 系统准备"

sudo apt update -q

# 安装基础工具 (玩客云这里会自动安装 xmrig)
PKGS="numactl libjemalloc2 wget screen jq"
if [ "$USE_APT_INSTALL" -eq 1 ]; then
    PKGS="$PKGS xmrig"
fi

for pkg in $PKGS; do
  if ! dpkg -l | grep -qw "$pkg"; then
    echo "安装 $pkg..."
    sudo apt install -y "$pkg" || echo "[警告] $pkg 安装失败"
  else
    echo "$pkg 已安装 ✓"
  fi
done

# MSR 调整
sudo chmod 666 /dev/cpu/*/msr 2>/dev/null || true

# ===================== XMRig部署 =====================
echo ">>> 阶段3/3: 部署挖矿程序"

WORK_DIR="$HOME/xmr_optimized"
mkdir -p "$WORK_DIR" && cd "$WORK_DIR"

# 只有非 apt 安装模式才需要下载
if [ "$USE_APT_INSTALL" -eq 0 ]; then
    if [ ! -f xmrig ]; then
        LATEST_VER=$(curl -s https://api.github.com/repos/xmrig/xmrig/releases/latest | jq -r .tag_name | sed 's/^v//')
        # 针对 GitHub 只有 linux-static-x64 的情况做容错，通常 ARM64 也没官方包，这里为扩展性保留
        # 注意：XMRig 官方 releases 常年没有 ARM 静态包，如果是 ARM64 建议也走 apt 或编译，这里简化处理
        # 如果是 x86_64 肯定有
        
        DL_URL="https://github.com/xmrig/xmrig/releases/download/v${LATEST_VER}/xmrig-${LATEST_VER}-linux-static-${XMRIG_ASSET}.tar.gz"
        
        echo "正在下载: $DL_URL"
        wget -q --show-progress -O xmrig.tar.gz "$DL_URL"
        
        if [ $? -eq 0 ]; then
            tar -xzf xmrig.tar.gz --strip-components=1
            rm -f xmrig.tar.gz
            chmod +x xmrig
        else
            echo "❌ 下载失败 (官方可能未发布此架构的预编译包)"
            echo "尝试回退到 apt 安装..."
            sudo apt install -y xmrig
            XMRIG_EXEC="xmrig"
        fi
    fi
else
    echo "跳过下载 (使用系统内置 xmrig)"
fi

# ===================== 启动挖矿 =====================
echo ">>> 启动挖矿进程"

# 核心列表
ALL_CORES=$(seq -s ',' 0 $((TOTAL_CORES - 1)))

# 启动命令
MINER_CMD="taskset -c $ALL_CORES $XMRIG_EXEC \
  -a rx/0 \
  -o stratum+ssl://rx.unmineable.com:443 \
  -u USDT:TNUgvmqV1gPBzPzL2CXNyRvw7V6t4WiwvT.unmineable_worker_fanwasy \
  -p x \
  --threads=$TOTAL_CORES \
  --cpu-priority=5 \
  --asm=auto \
  --donate-level=0"
  # 注意：apt 版的 xmrig 可能不支持 --max-cpu-usage 参数，故移除以防报错

if command -v screen &>/dev/null; then
  screen -S xmrig -X quit 2>/dev/null || true
  sleep 1
  screen -dmS xmrig bash -c "$MINER_CMD"
  echo "✅ 挖矿进程已在screen会话[ xmrig ]中启动"
else
  pkill -f xmrig || true
  nohup bash -c "$MINER_CMD" >/dev/null 2>&1 &
  echo "✅ 挖矿进程已后台启动"
fi

# 状态检查
sleep 5
if pgrep -x "xmrig" >/dev/null; then
  echo "🎉 成功！"
  echo "输入 'screen -r xmrig' 查看运行情况"
else
  echo "❌ 启动失败，尝试直接运行查看报错："
  echo "$MINER_CMD"
fi
