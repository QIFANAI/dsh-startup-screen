# 本目录：dsh-startup-screen 一键安装包

> 这份文件是给 **DSH 助手** 读的作业指令。用户把本目录或压缩包交给你时，默认意图是
> “把这个启动动画插件装进 DSH”。请直接执行，不要先问技术细节。

## 一、你要做的事

在 Windows 上运行（把 `<本目录>` 换成当前目录的绝对路径）：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "<本目录>\install.ps1" -FromAgent
```

如果 `powershell.exe` 不在 PATH，使用绝对路径：

```text
%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe
```

脚本会立即返回，然后在 **20 秒后**自动完成：

1. 定位 DSH 安装目录与 `dsh` CLI；
2. 备份 `%USERPROFILE%\.dsh\profiles\desktop` 的配置；
3. 完全关闭 DSH 桌面端；
4. 执行 `dsh plugin --profile desktop add <tgz>`；
5. 校验版本、依赖与插件入口；
6. 重新打开 DSH。

## 二、你必须补的一句话

脚本返回后，在 20 秒内给用户发一条短消息，例如：

> 安装已开始，DSH 会在约 20 秒后自动重启；重启后打开「设置 → 启动动画」即可。

不要在这 20 秒内继续跑长命令，否则 DSH 关闭时消息可能发不出去。

## 三、装完怎么验收

DSH 重启后运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "<本目录>\verify.ps1"
```

看到 `验收通过` 即可。日志在：

```text
%TEMP%\dsh-startup-screen-installer\logs\
```

## 四、常见失败与处理

| 现象 | 处理 |
|---|---|
| 找不到 `dsh` CLI | 让用户先打开一次 DSH 桌面端，完全退出后再运行；或改用 `-DshCli "<DSH安装目录>\resources\runtime\cli\bin\dsh.cmd"` |
| 找不到 profile | 同上：先打开一次 DSH，让它创建 `desktop` profile |
| 无法关闭 DSH | 让用户手动完全退出 DSH（含托盘图标），再运行 |
| `dsh plugin add` 失败 | 把日志路径发给用户；不要自行删除 `~/.dsh` |
| 装完设置页没有「启动动画」 | 再重启一次 DSH；仍没有就跑 `verify.ps1` 并把日志给维护者 |

## 五、边界（不要做）

- 不要手工往 `%USERPROFILE%\.dsh\profiles\desktop\cordis.patch.yml` 里加 `insert` 条目；
  安装器会自动处理历史重复注册（先备份再注释）。
- 不要执行 `npm i -g`，DSH 自带运行时与 pnpm。
- 不要删除或重置 `%USERPROFILE%\.dsh`、用户会话、用户配置。
- 不要修改 DSH 安装目录；本安装器只写 profile 与用户配置目录。
- 同一版本重复安装是无害的，但会多一次重启；不要连续重复触发。

## 六、给人类用户

不想让助手代跑，直接双击本目录的 `安装.cmd`（或 `INSTALL.cmd`）即可；
卸载双击 `卸载.cmd`（或 `UNINSTALL.cmd`）；验收双击 `验收.cmd`（或 `VERIFY.cmd`）。
更多说明见 `README.md`。