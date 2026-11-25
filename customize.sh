#!/system/bin/sh
# customize.sh — 安装/升级时执行
# 模块作者：酷安：一颗初心

ui_print() { echo "$1"; }

# 版本号直接从 module.prop 读取，避免刷入页与模块本体版本不一致。
APP_VER=$(sed -n 's/^version=//p' "$MODPATH/module.prop" 2>/dev/null | head -n 1)
APP_CODE=$(sed -n 's/^versionCode=//p' "$MODPATH/module.prop" 2>/dev/null | head -n 1)
[ -n "$APP_VER" ] || APP_VER="v2.7.2"
[ -n "$APP_CODE" ] || APP_CODE="14"

# 作者主页：安装时给一次音量上键跳转机会；不支持的环境只打印地址。
AUTHOR_URL=${PS_AUTHOR_URL:-https://www.coolapk.com/u/1361950}
AUTHOR_SCHEME=${PS_AUTHOR_SCHEME:-coolapk://www.coolapk.com/u/1361950}
COOLAPK_PKG=${PS_COOLAPK_PKG:-com.coolapk.market}
AM_BIN=${PS_AM:-/system/bin/am}
PM_BIN=${PS_PM:-/system/bin/pm}
GETEVENT_BIN=${PS_GETEVENT:-/system/bin/getevent}
KEY_WAIT=${PS_KEY_WAIT:-10}

ui_print " "
ui_print "  续航天平 PowerBalance"
ui_print "  ${APP_VER} · 酷安@一颗初心"
ui_print "  --------------------------------"
if command -v getprop >/dev/null 2>&1; then
  MODEL=$(getprop ro.product.model 2>/dev/null)
  ANDROID=$(getprop ro.build.version.release 2>/dev/null)
  ABI=$(getprop ro.product.cpu.abi 2>/dev/null)
  KERNEL=$(uname -r 2>/dev/null)
  ui_print "  设备：${MODEL:-未知}"
  ui_print "  Android ${ANDROID:-未知} · ${ABI:-未知}"
  ui_print "  内核：${KERNEL:-未知}"
  ui_print "  --------------------------------"
fi
ui_print "  CPU / GPU 双天平 · 续航自动优化"
ui_print "  低电量或息屏时降频，结束按原值还原"
ui_print " "
ui_print "  本次更新 · 对比 v2.7.1"
ui_print " "
ui_print "  优化"
ui_print "  · 电池状态：Charging slowly / 充电中 等识别"
ui_print "  · 卸载还原失败时保留备份与 state"
ui_print " "
ui_print "  修复"
ui_print "  · WebUI：日志导出异常会明确提示"
ui_print " "
ui_print "  自检：模块 25 项 / UI 121 项通过"
ui_print "  --------------------------------"
ui_print "  作者主页：coolapk.com/u/1361950"

# 安装时按音量上键打开作者主页：只在系统已启动、am/getevent 都可用时尝试。
if [ -x "$AM_BIN" ] && [ -x "$GETEVENT_BIN" ]; then
  ui_print "  ${KEY_WAIT} 秒内按【音量上键】打开主页，不按继续"
  KF="$MODPATH/.keycheck"
  : > "$KF" 2>/dev/null
  "$GETEVENT_BIN" -ql > "$KF" 2>/dev/null &
  GEPID=$!
  KEY=""
  i=0
  while [ "$i" -lt "$KEY_WAIT" ]; do
    sleep 1
    if grep -q 'KEY_VOLUMEUP' "$KF" 2>/dev/null; then
      KEY=up
      break
    fi
    i=$((i+1))
  done
  kill "$GEPID" 2>/dev/null
  wait "$GEPID" 2>/dev/null
  rm -f "$KF"
  if [ "$KEY" = "up" ]; then
    ui_print "  已按下音量上键，正在打开主页…"
    # 和 WebUI 同一套顺序：已装酷安先走 coolapk://；不接收再按包名拉起；
    # 仍失败才回退系统浏览器。不能保证每个酷安版本都接收深链，但不会卡住。
    if command -v "$PM_BIN" >/dev/null 2>&1 && "$PM_BIN" path "$COOLAPK_PKG" >/dev/null 2>&1; then
      "$AM_BIN" start -a android.intent.action.VIEW -c android.intent.category.BROWSABLE -d "$AUTHOR_SCHEME" -p "$COOLAPK_PKG" -f 0x10000000 >/dev/null 2>&1 ||
        "$AM_BIN" start -a android.intent.action.VIEW -c android.intent.category.BROWSABLE -d "$AUTHOR_URL" -p "$COOLAPK_PKG" -f 0x10000000 >/dev/null 2>&1 ||
        "$AM_BIN" start -a android.intent.action.VIEW -c android.intent.category.BROWSABLE -d "$AUTHOR_URL" -f 0x10000000 >/dev/null 2>&1
    else
      "$AM_BIN" start -a android.intent.action.VIEW -c android.intent.category.BROWSABLE -d "$AUTHOR_URL" -f 0x10000000 >/dev/null 2>&1
    fi
    if [ $? -eq 0 ]; then
      ui_print "  已尝试打开；安装继续"
    else
      ui_print "  打开失败，请手动访问上方主页地址"
    fi
  else
    ui_print "  未按键，继续安装"
  fi
else
  ui_print "  当前环境不支持打开浏览器，继续安装"
fi

ui_print " "
ui_print "  提示：游戏 / 相机 / 导航等重负载会变慢"
ui_print "  执行操作按钮 = 总开关（开 / 关）"
ui_print "  配置文件：模块目录/config"
ui_print " "

# 配置来源优先级：
#   1. 同 id 升级：保留 /data/adb/modules/power-balance/config
#   2. 从旧版 phone-saver 迁移（v1 老用户升级免重新配置）
#   3. 都没有：用 config.example 生成默认配置
SAME_CONF=${PS_SAME_CONF:-/data/adb/modules/power-balance/config}
SAME_STATS=${PS_SAME_STATS:-/data/adb/modules/power-balance/stats}
OLD_CONF=${PS_OLD_CONF:-/data/adb/modules/phone-saver/config}

if [ -f "$SAME_CONF" ]; then
  cp -f "$SAME_CONF" "$MODPATH/config"
  ui_print "  · 配置：保留原配置 + 补齐新键"
  # 升级迁移：给老配置补上新增的键（不覆盖用户已有值）
  CF="$MODPATH/config"
  if ! grep -q '^gov_switch=' "$CF" 2>/dev/null; then
    echo 'gov_switch=0' >> "$CF"
  fi
  if ! grep -q '^exclude=' "$CF" 2>/dev/null; then
    echo 'exclude=' >> "$CF"
  fi
  if ! grep -q '^thermal_boost=' "$CF" 2>/dev/null; then
    echo 'thermal_boost=1' >> "$CF"
  fi
  if ! grep -q '^batt_boost=' "$CF" 2>/dev/null; then
    echo 'batt_boost=1' >> "$CF"
  fi
  if ! grep -q '^gpu_save=' "$CF" 2>/dev/null; then
    echo 'gpu_save=1' >> "$CF"
  fi
elif [ -f "$OLD_CONF" ]; then
  cp -f "$OLD_CONF" "$MODPATH/config"
  ui_print "  · 配置：迁移 phone-saver + 补齐新键"
  ui_print "  · 注意：请手动卸载旧模块，避免双重调度"
  CF="$MODPATH/config"
  if ! grep -q '^gov_switch=' "$CF" 2>/dev/null; then
    echo 'gov_switch=0' >> "$CF"
  fi
  if ! grep -q '^exclude=' "$CF" 2>/dev/null; then
    echo 'exclude=' >> "$CF"
  fi
  if ! grep -q '^thermal_boost=' "$CF" 2>/dev/null; then
    echo 'thermal_boost=1' >> "$CF"
  fi
  if ! grep -q '^batt_boost=' "$CF" 2>/dev/null; then
    echo 'batt_boost=1' >> "$CF"
  fi
  if ! grep -q '^gpu_save=' "$CF" 2>/dev/null; then
    echo 'gpu_save=1' >> "$CF"
  fi
elif [ -f "$MODPATH/config.example" ]; then
  cp -f "$MODPATH/config.example" "$MODPATH/config"
  ui_print "  · 配置：生成默认配置"
else
  ui_print "  · 配置：未找到模板，跳过生成"
fi

# 保留累计统计（只迁移数字字段，重启后清空活动 uptime 基准，避免跨重启误计时）。
if [ -r "$SAME_STATS" ]; then
  read stat_seconds stat_entries stat_last < "$SAME_STATS"
  case "$stat_seconds" in ''|*[!0-9]*) stat_seconds=0 ;; esac
  case "$stat_entries" in ''|*[!0-9]*) stat_entries=0 ;; esac
  echo "$stat_seconds $stat_entries 0" > "$MODPATH/stats"
  ui_print "  · 统计：迁移 ${stat_seconds} 秒 / ${stat_entries} 次（基准清零）"
else
  ui_print "  · 统计：无历史记录，从零开始"
fi

# 权限（Magisk 环境里这些函数存在；离线测试环境没有就跳过）
if type set_perm_recursive >/dev/null 2>&1; then
  set_perm_recursive "$MODPATH" 0 0 0755 0644
  set_perm "$MODPATH/service.sh" 0 0 0755
  set_perm "$MODPATH/action.sh" 0 0 0755
  set_perm "$MODPATH/uninstall.sh" 0 0 0755
  set_perm "$MODPATH/customize.sh" 0 0 0755
  ui_print "  · 权限：脚本 0755 / 文件 0644"
else
  ui_print "  · 权限：跳过（非 Magisk 安装环境）"
fi

ui_print " "
ui_print "  --------------------------------"
ui_print "  安装完成 · ${APP_VER} · 重启后生效"
ui_print "  版本：${APP_VER} / versionCode ${APP_CODE}"
ui_print "  日志：模块目录/service.log"
ui_print " "
exit 0
