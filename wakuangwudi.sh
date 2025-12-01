echo ">>> 阶段1/3: 系统资源检查"

# 获取实际CPU核心数
TOTAL_CORES=$(nproc)
# 获取系统负载（1分钟）
LOAD_AVG=$(awk '{print $1}' /proc/loadavg)

# 计算可用挖矿核心 (使用所有核心)
MINING_CORES=$TOTAL_CORES

[ $MINING_CORES -le 0 ] && {
  echo "错误：未检测到可用的CPU核心。"
  exit 1
}

echo "总CPU核心: $TOTAL_CORES | 当前负载: $LOAD_AVG"
echo "将使用 ALL ($MINING_CORES) 核心进行挖矿 (CPU跑满)"

# 启用jemalloc优化 (内存分配优化，非大页内存，建议保留以防崩溃)
export LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libjemalloc.so.2

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

# --- [已移除] 大页内存配置代码块 ---

# 绕过MSR模块检查
echo "[信息] 跳过MSR模块加载"
sudo chmod 666 /dev/cpu/*/msr 2>/dev/null || true

# ===================== XMRig部署 =====================
echo ">>> 阶段3/3: 部署挖矿程序"

WORK_DIR="$HOME/xmr_optimized"
mkdir -p "$WORK_DIR" && cd "$WORK_DIR"

# 下载最新XMRig
if [ ! -f xmrig ]; then
  LATEST_VER=$(curl -s https://api.github.com/repos/xmrig/xmrig/releases/latest | jq -r .tag_name | sed 's/^v//')
  echo "下载 XMRig v${LATEST_VER}..."
  wget -q --show-progress -O xmrig.tar.gz \
    "https://github.com/xmrig/xmrig/releases/download/v${LATEST_VER}/xmrig-${LATEST_VER}-linux-static-x64.tar.gz"
  tar -xzf xmrig.tar.gz --strip-components=1
  rm -f xmrig.tar.gz
fi
chmod +x xmrig

# ===================== 启动挖矿 =====================
echo ">>> 启动挖矿进程"

# 生成核心列表
ALL_CORES=$(seq -s ',' 0 $((MINING_CORES - 1)))

# 构建启动命令
# 已移除 --randomx-1gb-pages 参数
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
  screen -dmS xmrig bash -c "$MINER_CMD"
  echo "挖矿进程已在screen会话[ xmrig ]中启动，使用 ALL 核心: $ALL_CORES"
else
  nohup bash -c "$MINER_CMD" >/dev/null 2>&1 &
  echo "挖矿进程已后台启动，使用 ALL 核心: $ALL_CORES"
fi

# 最终状态检查
sleep 5
if pgrep -x "xmrig" >/dev/null; then
  echo "✅ 挖矿进程运行正常！输入 'screen -r xmrig' 查看日志"
  echo "注意：由于移除了大页内存优化，哈希率(Hashrate)可能会降低 30%-50%。"
else
  echo "❌ 错误：进程启动失败，请检查日志。"
  echo "查看日志：tail -n 50 nohup.out"
fi
