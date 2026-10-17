# 实测结论与硬约束

**接手这个工程之前先读这一份。** 这里每条都是实测过的，不是推断。

---

## 1. 参考环境（实测基线，换机器需重测）

| 项 | 值 |
|---|---|
| DSH 桌面端 | `<DSH_INSTALL>\DeepSeek Harness.exe`（Electron 打包应用） |
| DSH 运行时 | `<DSH_INSTALL>\resources\runtime\`（node 24.18.1 / pnpm 11.7.0 / primary-runtime） |
| `dsh` CLI | `<DSH_INSTALL>\resources\runtime\cli\bin\dsh.cmd` |
| DSH 用户目录 | `%USERPROFILE%\.dsh` |
| 当前 profile | `desktop`（桌面端专用，**由 Electron 独占**） |
| 内置 Python | `%USERPROFILE%\.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\python\python.exe`（3.12，含 numpy / Pillow） |
| 无头浏览器 | `C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe`（Edge 155） |
| 无头截图 | `msedge.exe --headless=new --virtual-time-budget=<ms>` |

---

## 2. ⚠ 窗口右上角 — □ ✕ 按钮：**插件侧无法隐藏**

**证据**（`<DSH_INSTALL>\resources\app.asar\lib\main.js`，`createWindow()`）：

```js
...process.platform === "win32" && primary ? {
  titleBarStyle: "hidden",
  titleBarOverlay: {
    height: 40,
    color: chromeFallbackFill(),
    symbolColor: nativeTheme.shouldUseDarkColors ? "#f9fafb" : "#0f1115"
  }
} : {},
```

- 这是 Electron 的 **`titleBarOverlay`**（Windows 原生标题栏覆盖层），**由宿主绘制，永远盖在网页内容之上**。任何 CSS / z-index / DOM 手段都盖不住它。
- 排除"自绘按钮"的可能：扫了 `@deepseek-ai` 下 **2168 个文件**，没有窗口控制按钮组件；`-webkit-app-region` 只出现在欢迎窗与菜单栏。
- 排除"走 IPC 改"的可能：`preload-app.cjs` 的 `exposeInMainWorld` 里**没有** `titleBar` / `windowControl` / `setTitleBarOverlay`。

**结论**：要隐藏只能改 DSH 的 Electron 主进程。而且去掉 `titleBarOverlay` 后应用**没有任何关闭/最小化控件**（它没有自绘替代件），等于用可用性换外观。**未做。**

**可选的替代**（都要动宿主，需明确授权）：
1. 改 `app.asar` 的窗口选项 + 同时给应用补一套自绘按钮 —— 工作量大，DSH 更新即失效。
2. 启动时进全屏、结束退出 —— 按钮消失，但窗口会闪一次全屏，与"纯窗口大小"矛盾。

---

## 3. 宿主服务可达性（批次 3 的实测表）

探测方式：在插件 `apply(ctx)` 里逐名 `ctx.get(name)`，并 await 关键方法，结果写 JSON。
用**隔离 web profile** 跑，不碰用户正在用的实例。

### 可达（19 个）

| 服务 | 关键方法 / 字段 | 用途 |
|---|---|---|
| `profileContext` | `.name` `.cwd` `.home` `.startedBundles` | profile 名 / 工作区 / 安装的 bundle |
| `pluginManager` | `listBundles()` `listPlugins()` `registries()` | **bundle 数 + version**（`@deepseek-ai/dsh-base` 的 version 即 DSH 版本） |
| `pluginInventory` | `list()` → `{ entries:[{fiberPhase,enabled,...}] }` | 插件条目数 / 活跃数 |
| `agentDefaultModel` | `currentSelection()` → `{ provider, model }` | 模型名 |
| `sandboxPolicy` | `.defaultMode` `.workspaceRoot` `resolve()` | **权限模式** |
| `sessions` | `list()` | 会话数 |
| `sessionPersistence` | `list()` `stat()` | 同上（备用路径） |
| `webServer` `connection` | `register()` `tapIndex()` / `requestRejection()` | 插件路由与信任栅栏 |
| `storage` `settings` `credentials` | — | 备用 |
| `tokenMeter` `sessionQuery` `jobs` | — | 备用 |
| `approval` `authorization` `officeToPdf` `workspaceChanges` | — | 备用 |

### 不可达（9 个，名字不对）

`session` `sessionStore` `model` `models` `workspace` `agentPresetRegistry`
`sessionStats` `attachment` `permission`

> 实际名字分别是 `sessions` / `agentDefaultModel` / `sandboxPolicy`。

### ⚠ 一个坑

`approval.effectivePolicy()` **在 `apply()` 阶段会抛**
（`Cannot read properties of undefined (reading 'seq')`，上下文未就绪）。
权限展示一律走 `sandboxPolicy`，不要用 `approval`。

### 实测取值（隔离 web profile，2026-10-17）

```json
{ "profile": "WEB", "workspace": "default-workspace",
  "version": "0.2.1-rc.1", "model": "deepseek-flash",
  "sandbox": "workspace-write", "bundleCount": 21,
  "plugins": 191, "activePlugins": 159, "sessions": 0 }
```

> `plugins: 191` 是**配置树条目数**，不是用户插件数。对外显示要用 `bundleCount`。

---

## 4. 音频素材电平基准

所有电平结论都必须**先把素材解码回 PCM 再量**：MP3 的字节统计只是压缩流特征，测不出响度。

| 素材 | 时长 | 峰值 | 活跃段 RMS |
|---|---|---|---|
| line-1 | 2.05s | −6.9 dBFS | −22.9 dB |
| line-2 | 1.24s | −4.9 dBFS | −22.3 dB |
| line-3 | 1.16s | −8.8 dBFS | −22.7 dB |
| line-4 | 1.27s | −5.9 dBFS | −22.6 dB |
| line-5 | 1.79s | −4.9 dBFS | −22.6 dB |
| **line-6（自制）** | **3.73s** | **−9.0 dBFS** | **−22.9 dB** |
| bgm（入库后） | 150.5s | −9.2 dBFS | −18.0 dB |

- **台词基准：活跃段 RMS ≈ −22.6 dBFS。** 新素材要对齐到这个值。
- BGM 入库前归一到 −18 dBFS，播放端再乘 `bgmVolume`（默认 0.2 → 混音约 −32 dBFS）。

### 技术坑

- 素材路由白名单只收 **`.mp3`**（`/^[a-z0-9._-]+\.mp3$/i`），WAV 必须转码。
- 本机无 ffmpeg / lame，转码走 **Windows Media Foundation `MediaTranscoder`**，
  且**只能在 Windows PowerShell 5.1（`powershell.exe`）下跑** —— pwsh 7 没有 WinRT 投影。
- `IAsyncAction` 交回来是裸 COM 对象，`AsTask` 重载解析不了 →
  脚本改成"点火后轮询输出文件大小直到不再增长"。
- ffmpeg 管道输出的 WAV，`RIFF`/`data` 长度字段可能是 `0xFFFFFFFF`（假时长 26843s），
  入库前必须重写尺寸正确的头。

---

## 5. 无头截图核对（改视觉必须走这一步）

用 `package/tools/layout-fixture.html`：加载**真实的** `splash.css` + `splash.js`，
没有预览页那层控制台遮挡。

```bash
EDGE="/c/Program Files (x86)/Microsoft/Edge/Application/msedge.exe"
BASE="file:///E:/dsh-startup-screen/package/tools/layout-fixture.html"

"$EDGE" --headless=new --disable-gpu --no-sandbox --hide-scrollbars \
  --force-device-scale-factor=1 --window-size=1600,1020 \
  --virtual-time-budget=7000 \
  --screenshot=".../shot.png" "$BASE?theme=dark"
```

- `?theme=light|dark` —— **两套都要看**。1.2.2 的"灯芯绒"、1.3.1 的鲸鱼褪色，
  都是只在浅色主题暴露的。
- `?speed=0.35` 可慢放（但实测 `--virtual-time-budget` 对 speed 的换算**不稳定**，
  别指望靠它精确定格）。
- **`--virtual-time-budget` 不可靠**：同一时间戳两次运行可能落在不同帧
  （一次是稳定的第 5 步，一次停在过渡中间）。多抓几个时间点挑稳定帧，
  **别拿过渡帧下结论**。

### 已经踩过的坑（都会让一次改动白做）

| 坑 | 现象 | 正解 |
|---|---|---|
| `radial-gradient(circle)` 默认按 **farthest-corner** 取尺寸 | 按百分比算的环带跑到元素外 | 显式写 `closest-side` |
| `mask` 简写 | 环形遮罩不生效，扇区溢出 | 用 `mask-image` + `mask-size`/`mask-repeat` 长写 |
| 规则 `repeating-linear-gradient` 做纹理 | 浅底读成灯芯绒，暗底读成刮痕 | 用 `feTurbulence` 随机纹理 |
| 用 `stop-opacity` 调 `currentColor` 做金属感 | 整个形状变半透明 = 图标褪色 | 实心底 + 叠加白/黑高光层 |
| 在 1× 截图里判断小图标 | 看不出"褪色" | 用 PIL 裁剪放大 4–5× 再看 |
| 反向断言匹配到注释 | 断言被自己的说明文字绊倒 | 先剥 `/* */` 再断言 |

---

## 6. profile 管理约束

- desktop profile **由 Electron 独占管理**：`dsh --profile desktop --dump-config`
  直接被拒（`profile "desktop" is managed exclusively by the Electron application`）。
  CLI 只被允许做 plugin 增删（`manageDesktopProfile: true`）。
- 装 / 升 / 卸插件**必须先完全退出桌面端**。运行中写 `package.json` 会被覆盖。
- 本机这个 desktop 版本（2026-09-29 构建）**没有** `desktop-plugins.lock.json`，
  所以实测 CLI 写入可以存活；但换版本后要重新确认。
- 隔离验证的通用做法：`DSH_HOME=<临时目录>` + `dsh plugin --profile web add <tgz>` +
  `dsh web --port <空闲端口> --no-open`。**永远不要拿用户正在用的实例做验证。**

---

## 7. 构建与验证

```cmd
scripts\verify.cmd    :: 4 套冒烟测试，当前 352 项断言
scripts\build.cmd     :: npm pack → releases\
```

- 测试在 `package/test/`：`smoke-host` / `smoke-splash` / `smoke-client` / `smoke-desktop-boot`。
- `smoke-splash` 里有大量**静态断言**（正则扫源码与 CSS），改了实现要同步改断言。
- **新增断言必须反向验证**：喂一个已知缺陷确认它真的报错，否则可能是恒真绿灯。
  本项目每一批都做过这一步。
