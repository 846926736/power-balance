#!/system/bin/sh
# service.sh — 续航天平 PowerBalance 主调度（自包含版，无外部依赖）
# 模块作者：酷安：一颗初心
#
# 行为：按配置轮询；满足省电条件（电量低 / 息屏(可选) / always）时
# 降频/换调度/（可选）下线部分大核，条件结束后按原值逐项还原。
# 安全：对 /sys 的写入全部经 write_node()（白名单强制）；cpu0 永不下线。
umask 022

MODDIR=${PHONESAVER_MODDIR:-${0%/*}}

# ============ 公共函数（原 lib/common.sh） ============

SYS_ROOT=${PHONESAVER_SYS_ROOT:-/sys}

# ---------- 日志 ----------
log() {
  echo "$(date '+%F %T') $*" >> "$MODDIR/service.log" 2>/dev/null
}

# 决策日志去重：同一原因连续出现只记一次（状态变化时才再记）
LOG_LAST_REASON=""
log_reason() {
  r="$1"
  if [ "$r" != "$LOG_LAST_REASON" ]; then
    log "$r"
    LOG_LAST_REASON="$r"
  fi
}

# 自适应轮询日志：独立去重通道，只记间隔变化
LOG_LAST_ADAPT=""
log_adaptive() {
  if [ "$1" != "$LOG_LAST_ADAPT" ]; then
    log "$1"
    LOG_LAST_ADAPT="$1"
  fi
}

# 漂移日志：独立去重通道，内容变化才记
LOG_LAST_DRIFT=""
log_drift() {
  if [ "$1" != "$LOG_LAST_DRIFT" ]; then
    log "$1"
    LOG_LAST_DRIFT="$1"
  fi
}

trim_log() {
  lines=${CFG_LOG_LINES:-500}
  case "$lines" in ''|*[!0-9]*) lines=500 ;; esac
  [ "$lines" -ge 10 ] 2>/dev/null || lines=10
  f="$MODDIR/service.log"
  [ -f "$f" ] || return 0
  n=$(wc -l < "$f" 2>/dev/null)
  case "$n" in ''|*[!0-9]*) return 0 ;; esac
  if [ "$n" -gt "$lines" ]; then
    tail -n "$lines" "$f" > "$f.trim" 2>/dev/null && mv -f "$f.trim" "$f"
  fi
  return 0
}

# ---------- 配置 ----------
reset_config() {
  CFG_ENABLED=1
  CFG_MODE=battery
  CFG_LEVEL=balanced
  CFG_THRESHOLD=30
  CFG_CORE_OFF=0
  CFG_SCREEN_OFF_SAVE=0
  CFG_GOV_SWITCH=0
  CFG_THERMAL=1
  CFG_BATT_BOOST=1
  CFG_GPU_SAVE=1
  CFG_GPU_DEVICES=""
  CFG_EXCLUDE=""
  UNKNOWN_KEYS=''
  CFG_POLL=60
  CFG_LOG_LINES=500
}

load_config() {
  reset_config
  [ -r "$MODDIR/config" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    line=${line%%#*}
    case "$line" in
      *=*) ;;
      *) continue ;;
    esac
    key=${line%%=*}
    val=${line#*=}
    key=$(printf '%s' "$key" | tr -d ' \t\r')
    # 值只去首尾空白：保留 exclude 内部空格分隔，同时避免 "level=light " 这类
    # 尾随空格把整键变成非法值、静默回退默认档
    val=$(printf '%s' "$val" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    [ -n "$key" ] || continue
    case "$key" in
      enabled)
        case "$val" in 0|1) CFG_ENABLED=$val ;; esac ;;
      mode)
        case "$val" in battery|always|off) CFG_MODE=$val ;; esac ;;
      level)
        case "$val" in light|balanced|extreme) CFG_LEVEL=$val ;; esac ;;
      threshold)
        case "$val" in
          ''|*[!0-9]*) ;;
          *) [ "$val" -ge 5 ] 2>/dev/null && [ "$val" -le 80 ] 2>/dev/null && CFG_THRESHOLD=$val ;;
        esac ;;
      core_off)
        case "$val" in 0|1) CFG_CORE_OFF=$val ;; esac ;;
      screen_off_save)
        case "$val" in 0|1) CFG_SCREEN_OFF_SAVE=$val ;; esac ;;
      gov_switch)
        case "$val" in 0|1) CFG_GOV_SWITCH=$val ;; esac ;;
      thermal_boost)
        case "$val" in 0|1) CFG_THERMAL=$val ;; esac ;;
      batt_boost)
        case "$val" in 0|1) CFG_BATT_BOOST=$val ;; esac ;;
      gpu_save)
        case "$val" in 0|1) CFG_GPU_SAVE=$val ;; esac ;;
      gpu_devices)
        # 手动指定 GPU devfreq 设备（逗号分隔，支持通配符）。
        # 去掉空格；只保留白名单字符（字母数字 _ . - ? * 逗号），其余整键丢弃。
        val=$(printf '%s' "$val" | tr -d ' ')
        case "$val" in
          ''|*[!A-Za-z0-9_.,?*-]*) ;;
          *) CFG_GPU_DEVICES=$val ;;
        esac
        ;;
      exclude)
        # 空格分隔的包名列表；只保留 [A-Za-z0-9_.]+，逐个校验
        CFG_EXCLUDE=""
        for p in $val; do
          case "$p" in
            *[!A-Za-z0-9_.]*|'') continue ;;
          esac
          if [ -z "$CFG_EXCLUDE" ]; then
            CFG_EXCLUDE=$p
          else
            CFG_EXCLUDE="$CFG_EXCLUDE $p"
          fi
        done
        ;;
      poll)
        case "$val" in
          ''|*[!0-9]*) ;;
          *) [ "$val" -ge 5 ] 2>/dev/null && [ "$val" -le 3600 ] 2>/dev/null && CFG_POLL=$val ;;
        esac ;;
      log_lines)
        case "$val" in
          ''|*[!0-9]*) ;;
          *) [ "$val" -ge 10 ] 2>/dev/null && [ "$val" -le 5000 ] 2>/dev/null && CFG_LOG_LINES=$val ;;
        esac ;;
      *)
        UNKNOWN_KEYS="$UNKNOWN_KEYS $key" ;;
    esac
  done < "$MODDIR/config"
  return 0
}

# ---------- sysfs 读写 ----------
node_get() {
  cat "$1" 2>/dev/null
}

# 白名单（SPEC 第 4 节）。cpu0/online 显式拒绝：cpu0 永不写入。
# GPU（devfreq 标准接口）也纳入白名单。机型无关：devfreq 设备目录名各家不一
# （kgsl/mali/g3d/gpufreq/sgx...），所以白名单放开到"任意 devfreq 设备的
# max/min_freq"；实际写哪些设备由 gpu_dev_list 发现逻辑决定，白名单只是最后一道防线。
whitelisted() {
  case "$1" in
    "$SYS_ROOT"/devices/system/cpu/cpu0/online)
      return 1 ;;
    "$SYS_ROOT"/devices/system/cpu/cpufreq/policy[0-9]*/scaling_max_freq|\
    "$SYS_ROOT"/devices/system/cpu/cpufreq/policy[0-9]*/scaling_min_freq|\
    "$SYS_ROOT"/devices/system/cpu/cpufreq/policy[0-9]*/scaling_governor|\
    "$SYS_ROOT"/devices/system/cpu/cpufreq/policy[0-9]*/walt/hispeed_freq|\
    "$SYS_ROOT"/devices/system/cpu/cpu[0-9]*/online)
      return 0 ;;
    "$SYS_ROOT"/class/devfreq/*/max_freq|\
    "$SYS_ROOT"/class/devfreq/*/min_freq)
      return 0 ;;
  esac
  return 1
}

# 唯一合法的 sysfs 写入口：先校验白名单，失败重试一次。
write_node() {
  wp=$1
  wv=$2
  if ! whitelisted "$wp"; then
    log "reject write, not whitelisted: $wp"
    return 1
  fi
  if printf '%s\n' "$wv" > "$wp" 2>/dev/null; then
    return 0
  fi
  sleep 1
  if printf '%s\n' "$wv" > "$wp" 2>/dev/null; then
    log "write retry ok: $wp=$wv"
    return 0
  fi
  log "write failed: $wp (target value: $wv)"
  return 1
}

# ---------- 备份 / 还原 ----------
BK="$MODDIR/backup"
STATE="$MODDIR/state"
LOCK="$MODDIR/lock"
STATS="$MODDIR/stats"

esc_path() {
  printf '%s' "$1" | tr '/' '_'
}

# 备份节点原值（只在第一次写入前做一次；已存在则不动）
backup_node() {
  bp=$1
  [ -d "$BK" ] || mkdir -p "$BK" 2>/dev/null
  bf="$BK/$(esc_path "$bp")"
  if [ -f "$bf" ]; then
    return 0
  fi
  bv=$(node_get "$bp")
  if [ -z "$bv" ]; then
    log "backup skipped, node unreadable: $bp"
    return 1
  fi
  if printf '%s\n%s\n' "$bp" "$bv" > "$bf" 2>/dev/null; then
    return 0
  fi
  log "backup failed: $bp"
  return 1
}

# 按安全顺序还原全部备份：governor -> max -> min -> hispeed -> online。
# 还原也走 write_node（白名单同样生效）。
# 写失败的备份文件保留，等下一轮轮询或下次开机自愈重试；
# 只有全部成功才清空 backup 与 state，保证"所有改动可逆"成立。
restore_all() {
  if [ ! -d "$BK" ]; then
    rm -f "$STATE" 2>/dev/null
    return 0
  fi
  RA_FAIL=0
  for stage in governor max_freq min_freq hispeed online; do
    for bf in "$BK"/*; do
      [ -f "$bf" ] || continue
      case "$bf" in
        *"$stage"*) ;;
        *) continue ;;
      esac
      p=$(sed -n '1p' "$bf" 2>/dev/null)
      v=$(sed -n '2p' "$bf" 2>/dev/null)
      if [ -z "$p" ] || [ -z "$v" ]; then
        log "backup file malformed, dropped: $bf"
        rm -f "$bf"
        continue
      fi
      if write_node "$p" "$v"; then
        log "restored $p=$v"
        rm -f "$bf"
      else
        RA_FAIL=1
        log "RESTORE FAILED: $p (expected $v); backup kept for retry"
      fi
    done
  done
  if [ "$RA_FAIL" = "1" ]; then
    log "restore incomplete; will retry next poll/boot"
    return 1
  fi
  rmdir "$BK" 2>/dev/null
  rm -f "$STATE" 2>/dev/null
  return 0
}

# ---------- 频率选取 ----------
policy_list() {
  ls "$SYS_ROOT/devices/system/cpu/cpufreq" 2>/dev/null | grep '^policy[0-9]*$' | sort
}

# 输出目标频率：从该 policy 的 scaling_available_frequencies 里
# 选 <= base*pct/100 的最大档；列表缺失时输出 "approx:<值>"。
# 注意：调用方必须用 $(...) 取输出，APPROX 无法通过子 shell 传回。
pick_freq() {
  pd=$1
  pct=$2
  hwmin=$(node_get "$pd/cpuinfo_min_freq")
  hwmax=$(node_get "$pd/cpuinfo_max_freq")
  cur_max=$(node_get "$pd/scaling_max_freq")
  # base 优先取当前生效上限（scaling_max_freq）：ROM 温控/厂商守护可能已把它
  # 压低，若以 cpuinfo_max_freq 为基准，算出的目标会把温控压过的频率重新抬高，
  # 省电反而变成放开限制。读不到再退回 cpuinfo_max_freq。
  base=$cur_max
  case "$base" in
    ''|*[!0-9]*) base=$hwmax ;;
  esac
  case "$base" in
    ''|*[!0-9]*) echo ""; return 1 ;;
  esac
  want=$(( base * pct / 100 ))
  av=$(node_get "$pd/scaling_available_frequencies")
  # 可用频率列表必须非空且全是数字才做精确选档
  av_ok=1
  if [ -z "$av" ]; then
    av_ok=0
  else
    for f in $av; do
      case "$f" in
        ''|*[!0-9]*) av_ok=0 ;;
      esac
    done
  fi
  if [ "$av_ok" != "1" ]; then
    # 列表缺失或异常：近似模式，直接用计算值（内核会自行归到最近档）
    echo "approx:$want"
    return 0
  fi
  best=""
  for f in $av; do
    [ "$f" -le "$want" ] 2>/dev/null || continue
    if [ -z "$best" ] || [ "$f" -gt "$best" ]; then
      best=$f
    fi
  done
  if [ -z "$best" ]; then
    # 目标低于全部可选档：取最低档。部分平台 available_frequencies 为降序
    # （如高通 812M -> 315M），不能假设首项最小。
    for f in $av; do
      case "$f" in
        ''|*[!0-9]*) continue ;;
      esac
      if [ -z "$best" ] || [ "$f" -lt "$best" ]; then
        best=$f
      fi
    done
  fi
  case "$best" in
    ''|*[!0-9]*) echo ""; return 1 ;;
  esac
  # 不越过硬件下限
  case "$hwmin" in
    [0-9]*) [ "$best" -lt "$hwmin" ] 2>/dev/null && best=$hwmin ;;
  esac
  # 不越过硬件上限
  [ "$best" -gt "$base" ] 2>/dev/null && best=$base
  echo "$best"
  return 0
}

# ---------- GPU（devfreq 标准接口，机型无关） ----------
# GPU 设备发现（通用性核心，两步走）：
#   1. CFG_GPU_DEVICES 配置非空 -> 用户手动指定：按逗号分隔的模式（支持 shell
#      通配符，如 "13000000.mali" 或 "*kgsl*"）匹配目录名，指定即信任——任何
#      冷门命名都能覆盖；安全仍由白名单（只许写 max/min_freq）+ 备份还原兜底。
#   2. 未配置 -> 启发式自动发现：先过"非 GPU 设备"排除表（GPU 总线/带宽监控/
#      内存/L3/NPU 一律排除，压它们副作用不可控），再匹配主流厂商 GPU 命名
#      （kgsl/adreno/mali/g3d/gpufreq/sgx/pvr）。宁漏勿错：命名不认识就跳过，
#      用户可转手动模式。
# 两步共用同一节点有效性标准：max_freq 可读，且 available_frequencies 或
# cur_freq 含数字——与 CPU 相同的"只动读得到的节点"。
# 输出全部命中设备（每行一个，带尾斜杠）；一个都没有返回 1。
gpu_dev_list() {
  gdl_out=''
  for gd in "$SYS_ROOT"/class/devfreq/*/; do
    [ -d "$gd" ] || continue
    [ -r "${gd}max_freq" ] || continue
    gname=${gd%/}
    gname=${gname##*/}
    if [ -n "$CFG_GPU_DEVICES" ]; then
      gdl_hit=0
      gdl_oifs=$IFS
      IFS=,
      for gpat in $CFG_GPU_DEVICES; do
        case "$gpat" in
          ''|-*|*[!A-Za-z0-9_.?*]*) continue ;;
        esac
        case "$gname" in
          $gpat) gdl_hit=1 ;;
        esac
      done
      IFS=$gdl_oifs
      [ "$gdl_hit" = "1" ] || continue
    else
      case "$gname" in
        # 排除表：GPU 总线 / 带宽监控 / 内存类设备绝不碰
        *bus*|*bwmon*|*bw|*ddr*|*llcc*|*memlat*|*mem*|*noc*|*l3*|*dsu*|*npu*|*cdsp*|*adsp*|*modem*|*mdss*)
          continue ;;
        # 主流厂商 GPU 命名：高通 kgsl/adreno、Mali（MTK/瑞芯微/麒麟）、
        # Exynos g3d、MTK gpufreq、Imagination sgx/pvr、通用 gpu 字样
        *gpu*|*kgsl*|*mali*|*g3d*|*gpufreq*|*sgx*|*pvr*|*adreno*) ;;
        *) continue ;;
      esac
    fi
    gdl_ok=0
    gdl_v=$(node_get "${gd}available_frequencies")
    case "$gdl_v" in
      *[0-9]*) gdl_ok=1 ;;
    esac
    if [ "$gdl_ok" = "0" ]; then
      gdl_v=$(node_get "${gd}cur_freq")
      case "$gdl_v" in
        [0-9]*) gdl_ok=1 ;;
      esac
    fi
    [ "$gdl_ok" = "1" ] || continue
    gdl_out="$gdl_out$gd
"
  done
  case "$gdl_out" in
    '') return 1 ;;
  esac
  printf '%s' "$gdl_out"
  return 0
}

# GPU 频率选取：从 available_frequencies 里选 <= base*pct/100 的最大档；
# base 取当前 max_freq（缺失时回退 cur_freq）。列表缺失时输出 "approx:<值>"。
pick_gpu_freq() {
  gd=$1
  pct=$2
  base=$(node_get "${gd}max_freq")
  case "$base" in
    ''|*[!0-9]*) base=$(node_get "${gd}cur_freq") ;;
  esac
  case "$base" in
    ''|*[!0-9]*) echo ""; return 1 ;;
  esac
  want=$(( base * pct / 100 ))
  av=$(node_get "${gd}available_frequencies")
  av_ok=1
  if [ -z "$av" ]; then
    av_ok=0
  else
    for f in $av; do
      case "$f" in
        ''|*[!0-9]*) av_ok=0 ;;
      esac
    done
  fi
  if [ "$av_ok" != "1" ]; then
    echo "approx:$want"
    return 0
  fi
  best=""
  for f in $av; do
    [ "$f" -le "$want" ] 2>/dev/null || continue
    if [ -z "$best" ] || [ "$f" -gt "$best" ]; then
      best=$f
    fi
  done
  if [ -z "$best" ]; then
    # 目标低于全部可选档：取最低档（列表可能为降序，见 pick_freq 注释）
    for f in $av; do
      case "$f" in
        ''|*[!0-9]*) continue ;;
      esac
      if [ -z "$best" ] || [ "$f" -lt "$best" ]; then
        best=$f
      fi
    done
  fi
  case "$best" in
    ''|*[!0-9]*) echo ""; return 1 ;;
  esac
  echo "$best"
  return 0
}

# ---------- 电量（廉价路径优先） ----------
# 结果写入全局：BAT_LEVEL(0-100) BAT_STATUS BAT_CHARGING(0|1)。读不到返回 1。
# 读取顺序：
#   1. 测试钩子 PHONESAVER_BATTERY_FILE（第1行=电量，第2行=状态）
#   2. /sys/class/power_supply/battery/{capacity,status}  —— 纯 sysfs，零 binder
#   3. dumpsys battery 兜底（个别 ROM 的 power_supply 不标准时）
read_battery() {
  BAT_LEVEL=""
  BAT_STATUS=""
  BAT_CHARGING=0
  BATT_DUMP=""
  if [ -n "$PHONESAVER_BATTERY_FILE" ] && [ -r "$PHONESAVER_BATTERY_FILE" ]; then
    BAT_LEVEL=$(sed -n '1p' "$PHONESAVER_BATTERY_FILE" 2>/dev/null | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    BAT_STATUS=$(sed -n '2p' "$PHONESAVER_BATTERY_FILE" 2>/dev/null | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
  else
    supp="$SYS_ROOT/class/power_supply/battery"
    # status 只去首尾空白，保住 "Not charging" 这类带空格的状态词
    BAT_LEVEL=$(node_get "$supp/capacity" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    BAT_STATUS=$(node_get "$supp/status" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    if ! printf '%s' "$BAT_LEVEL" | grep -q '^[0-9][0-9]*$' 2>/dev/null; then
      BATT_DUMP=$(dumpsys battery 2>/dev/null)
      BAT_LEVEL=$(printf '%s\n' "$BATT_DUMP" | sed -n 's/.*level: \([0-9][0-9]*\).*/\1/p' | head -n 1)
      BAT_STATUS=$(printf '%s\n' "$BATT_DUMP" | sed -n 's/.*status: \(.*\)/\1/p' | head -n 1)
    fi
  fi
  case "$BAT_LEVEL" in
    ''|*[!0-9]*) return 1 ;;
  esac
  [ "$BAT_LEVEL" -le 100 ] 2>/dev/null || return 1
  # 个别 ROM 开机早期 battery/status 为空或 Unknown，用 dumpsys 兜底，
  # 否则会把“插着电”误判成放电。
  case "$BAT_STATUS" in
    ''|Unknown|unknown)
      if [ -z "$BATT_DUMP" ]; then
        BATT_DUMP=$(dumpsys battery 2>/dev/null)
      fi
      BAT_STATUS=$(printf '%s\n' "$BATT_DUMP" | sed -n 's/.*status: *\(.*\)/\1/p' | head -n 1 | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
      ;;
  esac
  case "$BAT_STATUS" in
    1) BAT_STATUS="Unknown" ;;
    2) BAT_STATUS="Charging" ;;
    3) BAT_STATUS="Discharging" ;;
    4) BAT_STATUS="Not charging" ;;
    5) BAT_STATUS="Full" ;;
  esac
  # 开机更早期连 status 都是 Unknown 时，至少用充电器 online 节点区分
  # “接着电”和“没接电”，避免低电量插电开机被误降频。
  case "$BAT_STATUS" in
    ''|Unknown|unknown)
      online=""
      for ps in usb charger ac wireless; do
        p="$SYS_ROOT/class/power_supply/$ps"
        [ -r "$p/online" ] || continue
        v=$(node_get "$p/online" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        case "$v" in
          1) online=1; break ;;
          0) [ -z "$online" ] && online=0 ;;
        esac
      done
      case "$online" in
        1) BAT_STATUS="Mains" ;;
        0) BAT_STATUS="Unplugged" ;;
      esac
      ;;
  esac
  case "$BAT_STATUS" in
    2|5|Mains|[Nn]ot\ charging)
      BAT_CHARGING=1 ;;
    Charging*|charging*|CHARGING*|Full*|FULL*|full*|充电中*|正在充电*|已充满*|充电完成*)
      BAT_CHARGING=1 ;;
  esac
  return 0
}

# 电池温度（单位 0.1℃，如 355 = 35.5℃）。读不到置空。
read_temp() {
  BAT_TEMP=''
  if [ -n "$PHONESAVER_TEMP_FILE" ] && [ -r "$PHONESAVER_TEMP_FILE" ]; then
    BAT_TEMP=$(sed -n '1p' "$PHONESAVER_TEMP_FILE" 2>/dev/null | tr -d ' \t\r')
  else
    BAT_TEMP=$(node_get "$SYS_ROOT/class/power_supply/battery/temp" | tr -d ' \t\r')
  fi
  case "$BAT_TEMP" in
    ''|*[!0-9]*) BAT_TEMP='' ;;
  esac
}

# ---------- 屏幕状态 ----------
# 返回码：0=息屏 1=亮屏 2=未知。全部走廉价 sysfs。
# fb0/blank: 0=亮屏(unblank)，非 0=息屏；DRM 时代无 fb0 时读 card*-DSI-*/enabled。
read_screen() {
  blank="$SYS_ROOT/class/graphics/fb0/blank"
  if [ -r "$blank" ]; then
    v=$(node_get "$blank" | tr -d ' \t\r')
    case "$v" in
      0) return 1 ;;
      ''|*[!0-9]*) ;;
      *) return 0 ;;
    esac
  fi
  for d in "$SYS_ROOT"/class/drm/card*-*/enabled; do
    [ -e "$d" ] || continue
    v=$(node_get "$d" | tr -d ' \t\r')
    case "$v" in
      on|1|enabled) return 1 ;;
      off|0|disabled) return 0 ;;
    esac
  done
  return 2
}

# ---------- 前台应用与排除名单 ----------
# 读取当前前台包名；测试钩子 PHONESAVER_FOREGROUND_FILE 优先。
get_foreground_package() {
  if [ -n "$PHONESAVER_FOREGROUND_FILE" ] && [ -r "$PHONESAVER_FOREGROUND_FILE" ]; then
    sed -n '1p' "$PHONESAVER_FOREGROUND_FILE" 2>/dev/null | tr -d ' \t\r'
    return 0
  fi
  # 不用带 "/" 的 sed 字符类（部分 ROM 的 toybox sed 会挂）；包名只含 [A-Za-z0-9_.]
  dumpsys activity activities 2>/dev/null | sed -n \
    -e 's/.*mResumedActivity:.*u[0-9][0-9]* \([A-Za-z0-9_.]*\)[^A-Za-z0-9_.].*/\1/p' \
    -e 's/.*topResumedActivity=ActivityRecord{[^ ]* u[0-9][0-9]* \([A-Za-z0-9_.]*\)[^A-Za-z0-9_.].*/\1/p' | head -n 1
}

is_excluded() {
  case " $CFG_EXCLUDE " in
    *" $1 "*) return 0 ;;
  esac
  return 1
}

# ---------- 省电统计（模块私有文件；uptime 避免系统时间校准影响） ----------
# stats 格式：累计省电秒数 / 进入次数 / 上次记账 uptime 秒
read_uptime() {
  if [ -n "$PHONESAVER_UPTIME_FILE" ] && [ -r "$PHONESAVER_UPTIME_FILE" ]; then
    uptime_raw=$(sed -n '1p' "$PHONESAVER_UPTIME_FILE" 2>/dev/null)
  else
    uptime_raw=$(sed -n '1s/ .*//p' /proc/uptime 2>/dev/null)
  fi
  case "$uptime_raw" in
    ''|*[!0-9.]* ) echo 0; return ;;
  esac
  uptime_sec=${uptime_raw%%.*}
  case "$uptime_sec" in ''|*[!0-9]*) uptime_sec=0 ;; esac
  echo "$uptime_sec"
}

stats_load() {
  STATS_SECONDS=0
  STATS_ENTRIES=0
  STATS_LAST=0
  [ -r "$STATS" ] || return 0
  read -r STATS_SECONDS STATS_ENTRIES STATS_LAST < "$STATS"
  case "$STATS_SECONDS" in ''|*[!0-9]*) STATS_SECONDS=0 ;; esac
  case "$STATS_ENTRIES" in ''|*[!0-9]*) STATS_ENTRIES=0 ;; esac
  case "$STATS_LAST" in ''|*[!0-9]*) STATS_LAST=0 ;; esac
}

stats_save() {
  if printf '%s %s %s\n' "$STATS_SECONDS" "$STATS_ENTRIES" "$STATS_LAST" > "$STATS.tmp" 2>/dev/null; then
    mv -f "$STATS.tmp" "$STATS" 2>/dev/null
  fi
}

stats_tick() {
  [ "$PHONESAVER_ONCE" = "1" ] && [ "$PHONESAVER_STATS_FORCE" != "1" ] && return 0
  stats_load
  now=$(read_uptime)
  if [ "$1" = "1" ]; then
    if [ "$2" = "0" ]; then STATS_ENTRIES=$((STATS_ENTRIES + 1)); fi
    if [ "$STATS_LAST" -gt 0 ] && [ "$now" -ge "$STATS_LAST" ]; then
      STATS_SECONDS=$((STATS_SECONDS + now - STATS_LAST))
    fi
    STATS_LAST=$now
  else
    if [ "$STATS_LAST" -gt 0 ] && [ "$now" -ge "$STATS_LAST" ]; then
      STATS_SECONDS=$((STATS_SECONDS + now - STATS_LAST))
    fi
    STATS_LAST=0
  fi
  stats_save
}

# ---------- 状态文件与存活检查 ----------
saver_active() {
  [ -f "$STATE" ]
}

saver_level() {
  sed -n '2p' "$STATE" 2>/dev/null
}

# 状态文件：第 1 行 pid，第 2 行档位，第 3 行起每行 "policyN 目标频率"
# （第 3 行起用于全量漂移检测）

set_state() { # $1=level $2=多行 "<key> target" 文本（末尾自带换行）；$APPLY_FLAGS 非空时追加标志行
  # 原子写入（tmp + mv），避免 action.sh/WebUI 读到写了一半的状态文件
  {
    printf '%s\n%s\n%s' "$$" "$1" "$2"
    printf 'GPUN %s\n' "${GPU_N:-0}"
    if [ -n "$APPLY_FLAGS" ]; then
      printf '%s\n' "$APPLY_FLAGS"
    fi
  } > "$STATE.tmp" 2>/dev/null && mv -f "$STATE.tmp" "$STATE" 2>/dev/null
  return 0
}

# 低电量加深：升一档
escalate() {
  case "$1" in
    light) echo balanced ;;
    *) echo extreme ;;
  esac
}

# 判断 pid 是否是一个还活着的 续航天平 service（防误杀无关进程）
owner_alive_saver() {
  opid=$1
  [ -n "$opid" ] || return 1
  [ -d "/proc/$opid" ] || return 1
  grep -q 'power-balance/service.sh' "/proc/$opid/cmdline" 2>/dev/null
}

# ============ 主调度 ============

trim_log
log "---- power-balance start (pid $$) sys=$SYS_ROOT ----"

# ---------- 单实例锁 ----------
if [ -f "$LOCK/pid" ]; then
  oldpid=$(cat "$LOCK/pid" 2>/dev/null)
  if owner_alive_saver "$oldpid"; then
    log "another instance ($oldpid) is running; exiting"
    exit 0
  fi
  rm -rf "$LOCK"
fi
# 残留锁目录但无 pid 文件（上次掉电/IO 失败）：清掉重来，
# 否则 mkdir 永远失败，服务会静默不启动。
if [ -d "$LOCK" ] && [ ! -f "$LOCK/pid" ]; then
  log "stale lock without pid; removing"
  rm -rf "$LOCK"
fi
mkdir "$LOCK" 2>/dev/null || {
  rm -rf "$LOCK" 2>/dev/null
  mkdir "$LOCK" 2>/dev/null || {
    log "cannot create lock; exiting"
    exit 0
  }
}
echo $$ > "$LOCK/pid"

# PHONESAVER_ONCE=1：只做一次决策然后退出（测试/手动单次），退出时不自动还原。
RESTORE_ON_EXIT=1
if [ "$PHONESAVER_ONCE" = "1" ]; then
  RESTORE_ON_EXIT=0
fi

cleanup() {
  # 防重入：清理过程中再收到信号不再触发
  trap - EXIT HUP INT TERM
  if [ "$RESTORE_ON_EXIT" = "1" ] && saver_active; then
    log "exit: restoring before stop"
    stats_tick 0 1
    restore_all
  fi
  if [ "$(cat "$LOCK/pid" 2>/dev/null)" = "$$" ]; then
    rm -rf "$LOCK"
  fi
  # 陷阱处理完必须退出，否则 shell 会回到主循环继续跑
  exit 0
}
trap cleanup EXIT HUP INT TERM

# ---------- 开机自愈：上次崩溃留下的状态先还原 ----------
# PHONESAVER_SKIP_HEAL=1：跳过自愈（测试钩子，模拟常驻服务的连续循环）
if saver_active && [ "$PHONESAVER_SKIP_HEAL" != "1" ]; then
  sp=$(sed -n '1p' "$STATE" 2>/dev/null)
  if [ "$sp" != "$$" ] && owner_alive_saver "$sp"; then
    log "state owned by live pid $sp, exiting (lock race)"
    exit 0
  fi
  log "stale state from previous run (pid $sp); restoring first"
  restore_all
fi

# ---------- 省电动作 ----------
# 下线最大的非 cpu0 集群里最多 2 个核（该集群至少留 1 个在线）
offline_top_cores() {
  best=""
  bestmax=0
  bestcpus=""
  for pol in $(policy_list); do
    case "$pol" in
      policy0) continue ;;
    esac
    pd="$SYS_ROOT/devices/system/cpu/cpufreq/$pol"
    ac=$(node_get "$pd/affected_cpus")
    case "$ac" in ''|*[!0-9\ ]*) continue ;; esac
    n=$(printf '%s' "$ac" | wc -w)
    [ "$n" -ge 2 ] 2>/dev/null || continue
    m=$(node_get "$pd/cpuinfo_max_freq")
    case "$m" in [0-9]*) ;; *) continue ;; esac
    if [ "$m" -gt "$bestmax" ] 2>/dev/null; then
      bestmax=$m
      best=$pol
      bestcpus=$ac
    fi
  done
  if [ -z "$best" ]; then
    log "core-off: no eligible cluster (need a multi-core non-policy0 cluster)"
    return 0
  fi
  cnt=0
  first=1
  for c in $bestcpus; do
    [ "$c" = "0" ] && continue
    if [ "$first" = "1" ]; then
      first=0
      continue
    fi
    [ "$cnt" -ge 2 ] && break
    onp="$SYS_ROOT/devices/system/cpu/cpu$c/online"
    on=$(node_get "$onp")
    [ "$on" = "0" ] && continue
    if backup_node "$onp" && write_node "$onp" "0"; then
      cnt=$((cnt + 1))
      log "offlined cpu$c (cluster $best)"
    fi
  done
  if [ "$cnt" = "0" ]; then
    log "core-off: nothing offlined"
  fi
  return 0
}

# 对全部 policy 应用某一档位（集群差异化：小核压更狠、大核留余量）
# 小核（cpuinfo_max_freq 最低的集群）跑的后台任务最多，压它收益最大；
# 大核（最高的集群）承担前台交互，留余量避免掉帧。极限档全部压到最低。
apply_level() {
  lvl=$1
  case "$lvl" in
    light) pl=90; pm=90; pb=95 ;;
    balanced) pl=65; pm=65; pb=75 ;;
    extreme) pl=0; pm=0; pb=0 ;;
    *) log "apply_level: bad level '$lvl'"; return 1 ;;
  esac
  TARGET0=''
  TARGET0_SET=''
  PAIRS=''
  # 先收集各集群 hwmax，分出 小核/中核/大核
  hm_min='' ; hm_max=0
  for pol in $(policy_list); do
    hm=$(node_get "$SYS_ROOT/devices/system/cpu/cpufreq/$pol/cpuinfo_max_freq")
    case "$hm" in
      ''|*[!0-9]*) continue ;;
    esac
    if [ -z "$hm_min" ] || [ "$hm" -lt "$hm_min" ] 2>/dev/null; then hm_min=$hm; fi
    [ "$hm" -gt "$hm_max" ] 2>/dev/null && hm_max=$hm
  done
  for pol in $(policy_list); do
    pd="$SYS_ROOT/devices/system/cpu/cpufreq/$pol"
    hm=$(node_get "$pd/cpuinfo_max_freq")
    pct=$pm
    case "$hm" in
      [0-9]*)
        if [ "$hm" = "$hm_min" ]; then
          pct=$pl
        elif [ "$hm" = "$hm_max" ]; then
          pct=$pb
        fi
        ;;
    esac
    if [ "$lvl" = "extreme" ]; then
      target=$(pick_freq "$pd" 0)
    else
      target=$(pick_freq "$pd" "$pct")
    fi
    if [ -z "$target" ]; then
      log "skip $pol (no usable freq info)"
      continue
    fi
    case "$target" in
      approx:*)
        target=${target#approx:}
        log "freq list missing for $pol, using approx target"
        ;;
    esac

    hwmin=$(node_get "$pd/cpuinfo_min_freq")
    cur_min=$(node_get "$pd/scaling_min_freq")

    # extreme：先把 min 降到硬件最低，再压 max（避免 max 低于 min 被夹）
    if [ "$lvl" = "extreme" ]; then
      case "$hwmin" in
        [0-9]*)
          if [ -n "$cur_min" ] && [ "$cur_min" -gt "$hwmin" ] 2>/dev/null; then
            if backup_node "$pd/scaling_min_freq"; then
              write_node "$pd/scaling_min_freq" "$hwmin"
              cur_min=$(node_get "$pd/scaling_min_freq")
            fi
          fi
          ;;
      esac
    fi

    # max 不得低于当前有效 min 与硬件下限
    case "$cur_min" in
      [0-9]*) [ "$target" -lt "$cur_min" ] 2>/dev/null && target=$cur_min ;;
    esac
    case "$hwmin" in
      [0-9]*) [ "$target" -lt "$hwmin" ] 2>/dev/null && target=$hwmin ;;
    esac

    # 调度器：仅 gov_switch=1 时才切换。默认不动调度器——降频已经够省，
    # 切调度器会改变 CPU 升频节奏，重负载场景（游戏/相机）反而容易卡顿。
    ag=$(node_get "$pd/scaling_available_governors")
    gov=""
    if [ "$CFG_GOV_SWITCH" = "1" ]; then
      case "$lvl" in
        balanced)
          case " $ag " in *" conservative "*) gov=conservative ;; esac
          ;;
        extreme)
          case " $ag " in
            *" powersave "*) gov=powersave ;;
            *" conservative "*) gov=conservative ;;
          esac
          ;;
      esac
    fi
    if [ -n "$gov" ]; then
      cur_gov=$(node_get "$pd/scaling_governor")
      if [ "$cur_gov" != "$gov" ]; then
        if backup_node "$pd/scaling_governor"; then
          write_node "$pd/scaling_governor" "$gov"
        fi
      fi
    fi

    # 记录本集群目标（仅当写入成功，供漂移检测比对）
    if backup_node "$pd/scaling_max_freq"; then
      if write_node "$pd/scaling_max_freq" "$target"; then
        PAIRS="$PAIRS$pol $target
"
      fi
    fi

    # walt hispeed：balanced/extreme 且该 policy 仍在用 walt 时同步压低
    gnow=$(node_get "$pd/scaling_governor")
    if [ "$lvl" != "light" ] && [ "$gnow" = "walt" ] && [ -e "$pd/walt/hispeed_freq" ]; then
      if backup_node "$pd/walt/hispeed_freq"; then
        write_node "$pd/walt/hispeed_freq" "$target"
      fi
    fi
  done

  # GPU 纳入天平（gpu_save，默认开）：devfreq 标准接口限 GPU 最高频。
  # 轻度 90% / 均衡 70% / 激进压到最低档且把 min 下探。
  # 机型无关：循环处理 gpu_dev_list 发现的全部 GPU 设备（kgsl/mali/g3d/...
  # 一视同仁，手动 gpu_devices 指定的也在这里生效），PAIRS 键带设备名；
  # 一台都没有则记日志跳过，CPU 照常。
  # GPU_N 记录"发现的设备数"：开关关闭时也只探测不写入——
  # 供 decide_and_apply 判断 gpu_save 0->1 时需要补生效（无设备机型恒 0，
  # 永不误触发）。
  GPU_N=0
  if [ "$CFG_GPU_SAVE" != "1" ]; then
    for gdir in $(gpu_dev_list); do
      GPU_N=$((GPU_N + 1))
    done
  else
    # 原子化多 GPU 限频：先算全部目标并做备份，再逐个写入；
    # 任一写入失败则回滚本批次已成功写入的 GPU，保持“全部成功或全部不变”。
    GPU_TODO=''   # "gdir target" 逐行
    GPU_BACKED='' # 已备份的 gdir 逐行（供回滚）
    for gdir in $(gpu_dev_list); do
      [ -d "$gdir" ] || continue
      gname=${gdir%/}
      gname=${gname##*/}
      case "$lvl" in
        light) gpct=90 ;;
        balanced) gpct=70 ;;
        *) gpct=0 ;;
      esac
      # extreme：先把 min 下探到最低可用档（避免 max 低于 min 被夹）
      if [ "$lvl" = "extreme" ]; then
        glow=$(pick_gpu_freq "$gdir" 0)
        gmin_cur=$(node_get "${gdir}min_freq")
        case "$glow" in
          [0-9]*)
            case "$gmin_cur" in
              [0-9]*)
                if [ "$gmin_cur" -gt "$glow" ] 2>/dev/null; then
                  if backup_node "${gdir}min_freq"; then
                    write_node "${gdir}min_freq" "$glow"
                  fi
                fi
                ;;
            esac
            ;;
        esac
      fi
      gtarget=$(pick_gpu_freq "$gdir" "$gpct")
      if [ -z "$gtarget" ]; then
        log "gpu $gname: no usable freq info; skip"
        continue
      fi
      case "$gtarget" in
        approx:*)
          gtarget=${gtarget#approx:}
          log "gpu $gname freq list missing, using approx target"
          ;;
      esac
      gmin_now=$(node_get "${gdir}min_freq")
      case "$gmin_now" in
        [0-9]*) [ "$gtarget" -lt "$gmin_now" ] 2>/dev/null && gtarget=$gmin_now ;;
      esac
      if backup_node "${gdir}max_freq"; then
        GPU_TODO="$GPU_TODO$gdir $gtarget
"
        GPU_BACKED="$GPU_BACKED$gdir
"
      else
        log "gpu $gname: backup failed, skip"
      fi
    done
    # 逐个写入；失败则回滚（含 extreme 先写过的 min_freq）
    GPU_FAIL=0
    GPU_OK=0
    while IFS= read -r gl; do
      [ -n "$gl" ] || continue
      gd=${gl%% *}
      gt=${gl#* }
      gname=${gd%/}
      gname=${gname##*/}
      if write_node "${gd}max_freq" "$gt"; then
        PAIRS="${PAIRS}gpu:$gname $gt
"
        GPU_OK=$((GPU_OK + 1))
      else
        GPU_FAIL=1
        log "gpu write failed: $gname"
        break
      fi
    done <<EOF
$GPU_TODO
EOF
    if [ "$GPU_FAIL" = "1" ]; then
      # 回滚本批次：max_freq 与 min_freq 的备份都还原；还原成功的备份删除，
      # 失败的保留（状态文件还在，条件结束后的 restore_all 会再兜底一次）。
      for gdir in $GPU_BACKED; do
        for gnode in max_freq min_freq; do
          bf="$BK/$(esc_path "${gdir}${gnode}")"
          [ -f "$bf" ] || continue
          p=$(sed -n '1p' "$bf" 2>/dev/null)
          v=$(sed -n '2p' "$bf" 2>/dev/null)
          if [ -n "$p" ] && [ -n "$v" ] && write_node "$p" "$v" >/dev/null 2>&1; then
            rm -f "$bf"
          fi
        done
      done
      # state 不得保留 gpu: 行：本批次未生效，否则 WebUI 显示"已限频"、
      # 漂移检测也会拿不存在的目标比对。
      PAIRS_NOGPU=''
      while IFS= read -r pl; do
        [ -n "$pl" ] || continue
        case "$pl" in
          gpu:*) continue ;;
        esac
        PAIRS_NOGPU="$PAIRS_NOGPU$pl
"
      done <<EOF
$PAIRS
EOF
      PAIRS=$PAIRS_NOGPU
      log "gpu atomic rollback: 某 GPU 写入失败，已回滚本批次 GPU 限频"
      GPU_N=0
    else
      GPU_N=$GPU_OK
      if [ "$GPU_N" = "0" ]; then
        log "gpu: no usable GPU devfreq device; skip"
      fi
    fi
  fi
  if [ "$lvl" = "extreme" ] && [ "$CFG_CORE_OFF" = "1" ]; then
    offline_top_cores
  fi
  set_state "$lvl" "$PAIRS"
  # gpu_applied 打实际成功写入的 GPU 数（回滚时为 0），不再只打开关值
  log "applied level=$lvl core_off=$CFG_CORE_OFF gpu_save=$CFG_GPU_SAVE gpu_applied=${GPU_N:-0} temp=${BAT_TEMP:-NA}"
  return 0
}

# ---------- 决策 ----------
decide_and_apply() {
  load_config
  BAT_LEVEL=''
  BAT_TEMP=''
  BAT_CHARGING=0
  THERMAL_ON=0
  BOOST_ON=0
  APPLY_FLAGS=''
  active=0
  saver_active && active=1
  eff_level=$CFG_LEVEL

  if [ "$CFG_ENABLED" != "1" ] || [ "$CFG_MODE" = "off" ]; then
    if [ "$active" = "1" ]; then
      log "disabled or mode=off: restoring"
      stats_tick 0 1
      restore_all
    fi
    return 0
  fi

  should=0
  case "$CFG_MODE" in
    always)
      should=1
      log_reason "mode=always -> save"
      ;;
    battery)
      if read_battery; then
        if [ "$BAT_CHARGING" = "1" ]; then
          should=0
          log_reason "battery=$BAT_LEVEL charging -> restore"
        elif [ "$BAT_LEVEL" -le "$CFG_THRESHOLD" ]; then
          should=1
          log_reason "battery=$BAT_LEVEL <= threshold=$CFG_THRESHOLD -> save"
        elif [ "$BAT_LEVEL" -ge $((CFG_THRESHOLD + 5)) ]; then
          should=0
          log_reason "battery=$BAT_LEVEL >= threshold+5=$((CFG_THRESHOLD + 5)) -> restore"
        else
          should=$active
          log_reason "battery=$BAT_LEVEL in band -> keep (active=$active)"
        fi
        # 低电量自动加深（batt_boost，默认开）：电量 <=15% 升一档，
        # >=20% 恢复（滞回），充电时不生效
        if [ "$CFG_BATT_BOOST" = "1" ] && [ "$BAT_CHARGING" = "0" ]; then
          cur_boost=0
          grep -q '^flags.*batt' "$STATE" 2>/dev/null && cur_boost=1
          if [ "$BAT_LEVEL" -le 15 ]; then
            nboost=1
          elif [ "$BAT_LEVEL" -ge 20 ]; then
            nboost=0
          else
            nboost=$cur_boost
          fi
          if [ "$nboost" = "1" ]; then
            eff_level=$(escalate "$eff_level")
            BOOST_ON=1
            log_reason "battery=$BAT_LEVEL <= 15 -> boost to $eff_level"
          fi
        fi
      else
        should=$active
        log_reason "battery unreadable -> keep (active=$active)"
      fi
      ;;
  esac

  # 息屏省电（可选开关）：亮屏规则之外，息屏时也应用省电（无视电量与充电）
  if [ "$should" = "0" ] && [ "$CFG_SCREEN_OFF_SAVE" = "1" ]; then
    read_screen
    sc=$?
    if [ "$sc" = "0" ]; then
      should=1
      log_reason "screen off -> save (screen_off_save)"
    elif [ "$sc" = "2" ]; then
      log_reason "screen state unknown -> battery rule only"
    fi
  fi

  # 高温保护（thermal_boost，默认开）：电池温度 >=45C 时自动切到激进档
  # 压频护电池，降到 <43C 才恢复（滞回）。排除名单应用前台时不生效。
  if [ "$CFG_THERMAL" = "1" ]; then
    read_temp
    case "$BAT_TEMP" in
      [0-9]*)
        if [ "$BAT_TEMP" -ge 450 ]; then
          should=1
          eff_level=extreme
          THERMAL_ON=1
          log_reason "thermal ${BAT_TEMP} >= 450 -> extreme boost"
        elif [ "$BAT_TEMP" -ge 430 ] && [ "$(saver_level)" = "extreme" ]; then
          should=1
          eff_level=extreme
          THERMAL_ON=1
          log_reason "thermal ${BAT_TEMP} in band -> keep extreme"
        fi
        ;;
    esac
  fi

  # 状态标志行（供 WebUI 显示 高温/低电量 标签）
  APPLY_FLAGS='flags'
  [ "$THERMAL_ON" = "1" ] && APPLY_FLAGS="$APPLY_FLAGS thermal"
  [ "$BOOST_ON" = "1" ] && APPLY_FLAGS="$APPLY_FLAGS batt"
  [ "$APPLY_FLAGS" = "flags" ] && APPLY_FLAGS=''

  # 前台排除名单：排除名单里的 App 在前台时绝不应用省电；
  # 若当前已处于省电状态则立即还原，保证满性能（游戏/重负载应用友好）。
  # 例外：高温保护（thermal_boost）优先于排除名单——护电池是硬约束，
  # 游戏白名单不能在 45C+ 时把降频也一起挡掉。
  # 排除名单为空时，不调用 dumpsys activity：省掉每轮一次 binder 查询。
  if [ "$should" = "1" ] && [ -n "$CFG_EXCLUDE" ]; then
    fg=$(get_foreground_package)
    if [ -n "$fg" ] && is_excluded "$fg"; then
      if [ "$THERMAL_ON" = "1" ]; then
        log "foreground $fg excluded, but thermal boost wins; keep saving"
      else
        log "foreground $fg excluded; skip save"
        if [ "$active" = "1" ]; then
          log "excluded app in foreground; restoring for full performance"
          stats_tick 0 1
          restore_all
        fi
        return 0
      fi
    fi
  fi

  if [ "$should" = "1" ]; then
    stats_tick 1 "$active"
    # 省电中改 gpu_save 开关：GPU 需要立即对齐，走整体重套用（CPU 目标不变）。
    # 0->1：state 里曾发现过 GPU 设备（GPUN>=1）但现在没有 gpu: 行 -> 补生效；
    # 1->0：state 里有 gpu: 行 -> 立即还原。没发现过设备（GPUN=0）不触发，
    # 避免无 GPU 机型每轮空转重套用。
    gpu_mismatch=0
    st_gpun=$(sed -n 's/^GPUN //p' "$STATE" 2>/dev/null | head -n 1)
    case "$st_gpun" in
      ''|*[!0-9]*) st_gpun='' ;;
    esac
    case "$CFG_GPU_SAVE" in
      0)
        if grep -q '^gpu:' "$STATE" 2>/dev/null; then
          gpu_mismatch=1
        fi
        ;;
      1)
        if [ -n "$st_gpun" ] && [ "$st_gpun" -ge 1 ] 2>/dev/null \
          && ! grep -q '^gpu:' "$STATE" 2>/dev/null; then
          gpu_mismatch=1
        fi
        ;;
    esac
    if [ "$active" = "0" ]; then
      apply_level "$eff_level"
    elif [ "$(saver_level)" != "$eff_level" ] || [ "$gpu_mismatch" = "1" ]; then
      log "config changed; re-applying from originals"
      restore_all
      apply_level "$eff_level"
    else
      # 全量漂移检测（仅记日志，不回写）：逐集群比对生效值与当时写入的目标，
      # 回写会跟温控打架，所以只把「被覆盖」这件事暴露出来。
      set -- $(tail -n +3 "$STATE" 2>/dev/null)
      dmsg=''
      while [ $# -ge 2 ]; do
        dpol=$1
        dtgt=$2
        shift 2
        case "$dpol" in
          policy[0-9]*)
            dcur=$(node_get "$SYS_ROOT/devices/system/cpu/cpufreq/$dpol/scaling_max_freq" | tr -d ' \t\r')
            ;;
          gpu:*)
            gdev=${dpol#gpu:}
            gdp="$SYS_ROOT/class/devfreq/$gdev/"
            if [ ! -r "${gdp}max_freq" ]; then
              continue
            fi
            dcur=$(node_get "${gdp}max_freq" | tr -d ' \t\r')
            ;;
          *) continue ;;
        esac
        case "$dcur" in
          ''|*[!0-9]*) continue ;;
        esac
        if [ "$dcur" != "$dtgt" ]; then
          dmsg="$dmsg $dpol max=$dcur target=$dtgt;"
        fi
      done
      if [ -n "$dmsg" ]; then
        log_drift "drift:$dmsg (ROM override?)"
      fi
    fi
  elif [ "$active" = "1" ]; then
    log "save conditions ended: restoring"
    stats_tick 0 1
    restore_all
  fi

  # 自适应轮询：空闲（未激活）且电量远离阈值时拉长间隔，减少自身唤醒耗电；
  # 靠近阈值、已激活、电量不可读时用正常间隔，保证响应速度。
  # 开了息屏省电时不拉伸：息屏后必须按 poll 节奏尽快进入省电，
  # 拉到 3 倍会让息屏省电最多延迟 3 倍才生效。
  NEXT_SLEEP=$CFG_POLL
  if [ "$should" = "0" ] && [ "$active" = "0" ] \
    && [ "$CFG_SCREEN_OFF_SAVE" != "1" ] && [ -n "$BAT_LEVEL" ]; then
    if [ "$BAT_LEVEL" -ge $((CFG_THRESHOLD + 15)) ] 2>/dev/null; then
      NEXT_SLEEP=$(( CFG_POLL * 3 ))
      [ "$NEXT_SLEEP" -gt 3600 ] && NEXT_SLEEP=3600
    fi
  fi
  log_adaptive "adaptive sleep=$NEXT_SLEEP"
  # 周期性截断日志：原来只在启动时 trim，长期运行日志会一直涨
  trim_log
  return 0
}

# 分段 sleep（每段最长 5 秒）：保证停止信号能尽快触发还原，
# 同时每段唤醒开销可忽略（挂起时 nanosleep 不会唤醒设备）。
sleep_chunked() {
  st_total=$1
  st_done=0
  while [ "$st_done" -lt "$st_total" ]; do
    st_chunk=$(( st_total - st_done ))
    [ "$st_chunk" -gt 10 ] && st_chunk=10
    sleep "$st_chunk" 2>/dev/null || return 0
    st_done=$(( st_done + st_chunk ))
  done
  return 0
}

# ---------- 主循环 ----------
load_config
log "config: mode=$CFG_MODE level=$CFG_LEVEL threshold=$CFG_THRESHOLD thermal=$CFG_THERMAL batt_boost=$CFG_BATT_BOOST screen_off_save=$CFG_SCREEN_OFF_SAVE gov_switch=$CFG_GOV_SWITCH gpu_save=$CFG_GPU_SAVE gpu_devices=[${CFG_GPU_DEVICES:-auto}] exclude=[${CFG_EXCLUDE:-none}]"
if [ -n "$UNKNOWN_KEYS" ]; then
  log "config: ignored unknown key(s):$UNKNOWN_KEYS"
fi
NEXT_SLEEP=$CFG_POLL
while [ ! -e "$MODDIR/disable" ] && [ ! -e "$MODDIR/remove" ]; do
  decide_and_apply
  if [ "$PHONESAVER_ONCE" = "1" ]; then
    break
  fi
  sleep_chunked "$NEXT_SLEEP"
done
log "service loop ended"
exit 0
