#!/system/bin/sh
# action.sh — 在 Magisk 管理器里点本模块的「执行操作」按钮时运行：
# 停用省电（enabled=0）并等待运行中的服务完成还原。（自包含版）
# 模块作者：酷安：一颗初心
umask 022

MODDIR=${PHONESAVER_MODDIR:-${0%/*}}
SYS_ROOT=${PHONESAVER_SYS_ROOT:-/sys}
BK="$MODDIR/backup"
STATE="$MODDIR/state"
LOCK="$MODDIR/lock"
CONF="$MODDIR/config"

log() {
  echo "$(date '+%F %T') $*" >> "$MODDIR/service.log" 2>/dev/null
}

node_get() {
  cat "$1" 2>/dev/null
}

# 白名单（与 service.sh 保持一致）。cpu0/online 显式拒绝。
# GPU（devfreq 标准接口）也纳入白名单；设备目录名机型各异，放开到
# "任意 devfreq 设备的 max/min_freq"，实际写哪些由 service 的发现逻辑决定。
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
    return 0
  fi
  log "write failed: $wp (target value: $wv)"
  return 1
}

esc_path() {
  printf '%s' "$1" | tr '/' '_'
}

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

owner_alive_saver() {
  opid=$1
  [ -n "$opid" ] || return 1
  [ -d "/proc/$opid" ] || return 1
  grep -q 'power-balance/service.sh' "/proc/$opid/cmdline" 2>/dev/null && return 0
  opcmd=$(tr '\0' ' ' < "/proc/$opid/cmdline" 2>/dev/null)
  case "$opcmd" in
    *"$MODDIR/service.sh"*) return 0 ;;
  esac
  return 1
}

log "action: user toggled module"

# 开关切换：enabled=1 -> 0（停用并等还原）；enabled=0 -> 1（重新启用）
cur=$(sed -n 's/^enabled=//p' "$CONF" 2>/dev/null | tr -d ' \t\r')
if [ "$cur" != "0" ]; then
  # 当前是启用状态 -> 停用
  if grep -q '^enabled=' "$CONF" 2>/dev/null; then
    sed -i 's/^enabled=.*/enabled=0/' "$CONF"
  else
    echo 'enabled=0' >> "$CONF"
  fi
  log "action: disabled by user"

  # 等运行中的服务在下一轮轮询里完成还原（最多 20 秒）；
  # 状态文件属于已死进程时不必等，直接走残留处理。
  i=0
  while [ $i -lt 20 ]; do
    [ -f "$STATE" ] || break
    sp=$(sed -n '1p' "$STATE" 2>/dev/null)
    owner_alive_saver "$sp" || break
    sleep 1
    i=$((i + 1))
  done

  if [ -f "$STATE" ]; then
    sp=$(sed -n '1p' "$STATE" 2>/dev/null)
    if owner_alive_saver "$sp"; then
      echo "已停用，运行中的服务会在下一轮轮询（最多 poll 秒）内自动还原。"
      echo "若长时间未还原，可重启手机或直接卸载模块。"
    else
      log "action: stale state (pid $sp dead), restoring directly"
      restore_all
      echo "检测到上次运行的残留状态，已直接还原为原始值。"
    fi
  else
    echo "已停用省电，被改过的 CPU 设置已还原。"
  fi
else
  # 当前是停用状态 -> 重新启用
  if grep -q '^enabled=' "$CONF" 2>/dev/null; then
    sed -i 's/^enabled=.*/enabled=1/' "$CONF"
  else
    echo 'enabled=1' >> "$CONF"
  fi
  log "action: enabled by user"
  echo "已启用省电。按当前模式（mode）在下一轮轮询生效。"
fi
echo "配置文件：$CONF"
echo "日志：$MODDIR/service.log"
exit 0
