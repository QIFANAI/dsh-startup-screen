# dsh-startup-screen 一键安装包

这是 **DeepSeek Harness（DSH）** 的开机启动动画插件安装包。
版本号、插件包文件名与 SHA256 见同目录的 `VERSION.txt`。

## 最快用法（人类用户）

1. 把压缩包**完整解压**到一个文件夹（不要在压缩包预览窗口里直接双击）。
2. 双击 `安装.cmd`（或 `INSTALL.cmd`）。
3. 安装器会自动关闭 DSH、安装插件、再重新打开 DSH。
4. 打开 DSH → **设置 → 启动动画**，按需调整。

> 安装前 DSH 会自动关闭。DSH 会保存会话，但正在输入的内容建议先发出去。

## 交给 DSH 装（推荐给非技术用户）

把解压后的**整个文件夹**交给 DSH，说一句“装一下这个插件”。
DSH 会读取本目录的 `AGENTS.md`，执行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\install.ps1" -FromAgent
```

脚本会立即返回，并在约 20 秒后自动关闭 DSH、安装、重启。
这段时间足够 DSH 把“正在安装”的回复发出来。

## 安装器做了什么

1. 自动定位 `DeepSeek Harness.exe` 与 `dsh` CLI（PATH、运行进程、卸载注册表、开始菜单快捷方式、常见安装目录）。
2. 读取 `%USERPROFILE%\.dsh\profiles\desktop`（或 `%DSH_HOME%\profiles\desktop`）。
3. 把 `package.json`、`pnpm-lock.yaml`、`pnpm-workspace.yaml`、`cordis.patch.yml` 备份到
   `<profile>\_backup\dsh-startup-install-<时间戳>\`。
4. 如果发现历史手工 `insert` 重复注册，先备份再注释掉（否则插件会 apply 两次）。
5. 完全关闭 DSH（最多优雅等待 25 秒，必要时强制结束残留进程）。
6. 执行 `dsh plugin --profile desktop add <tgz>`。
7. 校验：`dsh plugin list`、profile 依赖、`node_modules` 版本、插件入口文件。
8. 重新打开 DSH，并检查 `cordis.yml` 是否已包含插件条目。

安装日志：

```text
%TEMP%\dsh-startup-screen-installer\logs\
```

## 验收

双击 `验收.cmd`（或 `VERIFY.cmd`），或运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\verify.ps1"
```

看到 `验收通过` 即可。若 DSH 正在运行，可加端口做 HTTP 路由检查：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\verify.ps1" -Port <DSH端口>
```

不指定 `-Port` 时会跳过路由检查（只给警告，不算失败）。

## 卸载

双击 `卸载.cmd`（或 `UNINSTALL.cmd`），或运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\uninstall.ps1"
```

卸载只移除插件依赖，不删除用户设置 `%USERPROFILE%\.dsh\dsh-startup.json`。
需要彻底清除时，确认不需要保留配色/文案后再手动删除该文件。

## 环境要求

| 项 | 要求 |
|---|---|
| 系统 | Windows 10 / 11（本安装器只在 Windows 上实测） |
| DSH | DeepSeek Harness 桌面端，**至少打开过一次**（生成 `desktop` profile） |
| 权限 | 当前用户可写 `%USERPROFILE%\.dsh`；不需要管理员 |
| 网络 | 不需要；插件零运行时依赖，tgz 本地安装 |
| Node/npm | 不需要单独安装，DSH 自带运行时与 pnpm |

## 常见问题

**Q：提示找不到 dsh CLI。**
先打开一次 DSH 桌面端，完全退出后再运行。仍找不到时，手动指定：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\install.ps1" `
  -DshCli "D:\dsh\resources\runtime\cli\bin\dsh.cmd"
```

**Q：提示找不到 profile 目录。**
说明 DSH 还没初始化 `desktop` profile。先打开一次 DSH，等主界面出来，完全退出，再安装。

**Q：无法关闭 DSH。**
手动退出 DSH，包括托盘图标；确认任务管理器里没有 `DeepSeek Harness` 进程，再运行。

**Q：装完设置页没有「启动动画」。**
1. 再完全退出并重启一次 DSH；
2. 双击 `验收.cmd`；
3. 仍没有，把 `%TEMP%\dsh-startup-screen-installer\logs\` 最新日志发给维护者。

**Q：之前手工改过 `cordis.patch.yml`。**
安装器会检测 `insert` 重复注册并自动注释（原文件已备份）。不要同时保留手工条目和插件 bundle，
否则 `ctx.webServer.register()` 会重复注册同一路径并报错。

**Q：安装到一半失败，DSH 被关了怎么办。**
直接重新打开 DSH 即可；插件要么已装上，要么还是旧版本。备份目录在
`<profile>\_backup\dsh-startup-install-<时间戳>\`，可手动还原 `package.json` / `pnpm-lock.yaml` /
`cordis.patch.yml` 后运行 `dsh plugin --profile desktop install`。

## 文件清单

```text
AGENTS.md                  给 DSH 助手的作业指令
README.md                  本文件
VERSION.txt                版本、构建时间、tgz SHA256
install.ps1                安装器
common.ps1                 安装/验收/卸载共用函数
verify.ps1                 验收器
uninstall.ps1              卸载器
安装.cmd / INSTALL.cmd      双击安装
验收.cmd / VERIFY.cmd       双击验收
卸载.cmd / UNINSTALL.cmd    双击卸载
dsh-startup-screen-*.tgz   插件本体（npm pack 产物）
LICENSE                    插件 MIT 许可证
THIRD-PARTY-NOTICES.md     影音素材版权边界
```

## 安全边界

- 只写入 `%USERPROFILE%\.dsh`（或 `%DSH_HOME%`）下的 profile 与用户配置，不改 DSH 安装目录。
- 安装前必定备份 profile 配置；日志落在 `%TEMP%\dsh-startup-screen-installer\logs\`。
- 不执行 `npm i -g`，不安装全局依赖，不需要管理员权限。
- 安装器需要关闭并重启 DSH，这是 desktop profile 被 Electron 独占决定的；
  不是安装器可以绕过的限制。