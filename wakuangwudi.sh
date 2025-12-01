#!/bin/bash
echo ">>> 阶段1/3: 系统资源检查"

# ===================== 自动识别架构 =====================
ARCH=$(uname -m)
echo "检测到系统架构: $ARCH"

if [[ "$ARCH" == "x86_64" ]]; then
    XMRIG_FILE="x64"
    JEMALLOC_PATH="/usr/lib/x86_64-linux-gnu/libjemalloc.so.2"
elif [[ "$ARCH" == "aarch64" ]]; then
    XMRIG_FILE="arm64"
    JEMALLOC_PATH="/usr/lib/aarch64-linux-gnu/libjemalloc.so.2"
elif [[ "$ARCH" == "armv7l" ]]; then
    XMRIG_FILE="arm32" # 玩客云32位常见架构
    JEMALLOC_PATH="/usr/lib/arm-linux-gnueabihf/libjemalloc.so.2"
else
    echo "❌ 错误：不支持的架构 $ARCH"
    exit 1
fi
# =======================================================

# 获取实际CPU核心数
TOTAL_CORES=$(nproc)
MINING_CORES=$TOTAL_CORES

echo "总CPU核心: $TOTAL_CORES"
echo "将下载对应版本: xmrig-linux-static-${XMRIG_FILE}"

# 尝试查找真实的 jemalloc 路径 (如果预设不对)
FOUND_JEMALLOC=$(find /usr/lib -name libjemalloc.so.2 2>/dev/null | head -n 1)
if [ -n "$FOUND_JEMALLOC" ]; then
    export LD_PRELOAD=$FOUND_JEMALLOC
    echo "已启用内存优化: $FOUND_JEMALLOC"
else
    echo "[提示] 未找到 libjemalloc.so.2，将以普通模式运行"
fi

# ===================== 系统优化 =====================
echo ">>> 阶段2/3: 系统准备"

# 更新软件源
sudo apt update -q || echo "[警告] APT更新失败，继续..."

# 安装基础工具
for pkg in numactl libjemalloc2 wget screen jq; do
  if ! dpkg -l | grep -qw "$pkg"; then
    echo "安装 $pkg..."
    sudo apt install -y "$pkg" || echo "[警告] $pkg 安装失败"
  else
    echo "$pkg 已安装 ✓"
  fi
done

# 绕过MSR模块检查
sudo chmod 666 /dev/cpu/*/msr 2>/dev/null || true

# ===================== XMRig部署 =====================
echo ">>> 阶段3/3: 部署挖矿程序"

WORK_DIR="$HOME/xmr_optimized"
mkdir -p "$WORK_DIR" && cd "$WORK_DIR"

# 下载自动适配版本的 XMRig
if [ ! -f xmrig ]; then
  LATEST_VER=$(curl -s https://api.github.com/repos/xmrig/xmrig/releases/latest | jq -r .tag_name | sed 's/^v//')
  echo "下载 XMRig v${LATEST_VER} ($XMRIG_FILE)..."
  
  DOWNLOAD_URL="https://github.com/xmrig/xmrig/releases/download/v${LATEST_VER}/xmrig-${LATEST_VER}-linux-static-${XMRIG_FILE}.tar.gz"
  
  wget -q --show-progress -O xmrig.tar.gz "$DOWNLOAD_URL"
  
  if [ $? -ne 0 ]; then
      echo "❌ 下载失败！可能是网络问题或版本不存在。"
      exit 1
  fi

  tar -xzf xmrig.tar.gz --strip-components=1
  rm -f xmrig.tar.gz
fi
chmod +x xmrig

# ===================== 启动挖矿 =====================
echo ">>> 启动挖矿进程"

ALL_CORES=$(seq -s ',' 0 $((MINING_CORES - 1)))

# 启动命令
MINER_CMD="taskset -c $ALL_CORES ./xmrig \
  -a rx/0 \
  -o stratum+ssl://rx.unmineable.com:443 \
  -u USDT:TNUgvmqV1gPBzPzL2CXNyRvw7V6t4WiwvT.unmineable_worker_fanwasy \
  -p x \
  --threads=$MINING_CORES \
  --cpu-priority=5 \
  --asm=auto \
  --max-cpu-usage=100 \
  --donate-level=0"

if command -v screen &>/dev/null; then
  # 先杀掉旧进程
  screen -S xmrig -X quit 2>/dev/null || true
  sleep 1
  screen -dmS xmrig bash -c "$MINER_CMD"
  echo "✅ 挖矿进程已在screen会话[ xmrig ]中启动"
else
  pkill -f xmrig || true
  nohup bash -c "$MINER_CMD" >/dev/null 2>&1 &
  echo "✅ 挖矿进程已后台启动"
fi

# 最终状态检查
sleep 5
if pgrep -x "xmrig" >/dev/null; then
  echo "🎉 成功！进程 PID: $(pgrep -x xmrig)"
  echo "输入 'screen -r xmrig' 查看运行情况"
else
  echo "❌ 错误：进程启动失败。"
  echo "请尝试手动运行一次查看报错: cd ~/xmr_optimized && ./xmrig"
fi
