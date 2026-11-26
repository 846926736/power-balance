#!/system/bin/sh
# uninstall.sh — 模块被移除时把所有备份节点写回原值（自包含版）
# 模块作者：酷安：一颗初心
umask 022

MODDIR=${PHONESAVER_MODDIR:-${0%/*}}
SYS_ROOT=${PHONESAVER_SYS_ROOT:-/sys}
BK="$MODDIR/backup"
STATE="$MODDIR/state"
LOCK="$MODDIR/lock"

log() {
  echo "$(date '+%F %T') $*" >> "$MODDIR/service.log" 2>/dev/null
}

node_get() {
  cat "$1" 2>/dev/null
}

# 白名单（与 service.sh 保持一致）。cpu0/online 显式拒绝。
# GPU（devfreq 标准接口）也纳入白名单；设备目录名机型各异，放开到
# "任意 devfreq 设备的 max/min_freq"，否则 service 写过的设备会还原失败。
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
    log "write retry ok: $wp=$wv"
    return 0
  fi
  log "write failed: $wp (target value: $wv)"
  return 1
}

esc_path() {
  printf '%s' "$1" | tr '/' '_'
}

# 按安全顺序还原全部备份：governor -> max -> min -> hispeed -> online
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
        log "RESTORE FAILED: $p (expected $v)"
      fi
    done
  done
  if [ "$RA_FAIL" = "1" ]; then
    log "uninstall restore incomplete; backups kept"
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

# 卸载前先停掉仍在轮询的服务。否则 uninstall 还原完成后，服务的下一轮
# 可能再次压频，形成“卸载了但频率仍被改”的假象。
stop_saver() {
  pids=""
  for pf in "$LOCK/pid" "$STATE"; do
    [ -r "$pf" ] || continue
    p=$(sed -n '1p' "$pf" 2>/dev/null | tr -d ' \t\r')
    case "$p" in
      ''|*[!0-9]*) continue ;;
    esac
    owner_alive_saver "$p" || continue
    case " $pids " in
      *" $p "*) ;;
      *) pids="$pids $p" ;;
    esac
  done
  [ -n "$pids" ] || return 0
  log "uninstall: stopping service pid(s):$pids"
  kill $pids 2>/dev/null
  i=0
  while [ "$i" -lt 5 ]; do
    alive=0
    for p in $pids; do
      [ -d "/proc/$p" ] && alive=1
    done
    [ "$alive" = "0" ] && break
    sleep 1
    i=$((i + 1))
  done
  for p in $pids; do
    [ -d "/proc/$p" ] || continue
    owner_alive_saver "$p" || continue
    kill -9 "$p" 2>/dev/null
  done
  sleep 1
  return 0
}

log "uninstall: restoring all backed-up nodes"
stop_saver
restore_all
RR=$?
if [ "$RR" = "0" ]; then
  rm -rf "$MODDIR/lock" "$MODDIR/state" "$MODDIR/backup"
else
  log "uninstall incomplete: backup/state retained"
  rm -rf "$MODDIR/lock"
fi
log "uninstall done"
exit 0
