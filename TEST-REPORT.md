# 续航天平 PowerBalance v2.7.4 测试报告

## 版本

- 版本：v2.7.4
- versionCode：16
- 基线：v2.7.3 / versionCode 15

## 本次改动

- WebUI 底部新增「GitHub 更新」按钮，链接到 `https://github.com/846926736/power-balance/releases/latest`。
- 有命令桥时通过 `am start` 打开系统浏览器；无桥时回退 `window.open` / 当前页跳转。
- 原有作者主页、打赏、日志导出、排除名单逻辑不变。

## 回归结果

- 模块回归：**27 / 27 通过**
- WebUI 回归：**125 / 125 通过**
  - 新增 GitHub 链接地址、按钮文案、系统浏览器命令、操作提示四项检查。
- DOM ID：**50 个**，唯一，无重复或缺失
- `dash -n`：service / action / customize / uninstall 全部通过
- `node --check`：通过
- 安装器自检：显示 `v2.7.4 / versionCode 16`，模块 27 项 / UI 125 项通过
- 成品包 `unzip -t`：通过
- **直接用成品包内的脚本/HTML 重跑**：模块 27/27、WebUI 125/125，均通过
- 成品包逐文件与源码 `cmp` 一致，脚本权限保留

## 成品

- 文件：`power-balance-magisk-v2.7.4.zip`
- 大小：241,252 bytes
- SHA256：`909d49281ad95a2439a59c84abdc1d304ec20106826b9bf8a4155cabbb59925d`

## 未做 / 风险

- 未在真机 Magisk 环境刷入；GitHub 按钮实际打开浏览器、具体 ROM 的 sysfs 差异仍需真机确认。
