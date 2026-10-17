# 需要音频的字段清单

本文件列出启动动画里**所有会出声的槽位**，以及每个槽位当前用的是哪份素材。
数值与文件名直接从 `lib/splash.js` 抓取。

---

## 一、语音台词 —— 6 个槽位（前 5 个是真声素材，终幕是本地合成）

`line-1`–`line-5` 来自你提供的 `52xo4-igqdo-001.aac`，一一对应如下：

| 槽位 | 中文主字 | 英文副标题 | 素材文件 | 源素材 | 素材时长 | 出声时机 |
|---|---|---|---|---|---|---|
| `line-1` | 需要访问许可 | `ACCESS PERMISSION REQUIRED` | `lib/assets/line-1.mp3` | V1 (7.40–9.36s) | **1.96s** | 洗白后第一步，与文字渐显同时 |
| `line-2` | 身份资料确认 | `IDENTITY VERIFICATION` | `lib/assets/line-2.mp3` | V2 (11.29–12.45s) | **1.16s** | 第二步（身份卡 + 等确认） |
| `line-3` | 接收访问需求 | `ACCESS REQUEST RECEIVED` | `lib/assets/line-3.mp3` | V4 (14.76–15.83s) | **1.07s** | 第三步（鲸鱼标识一笔画成） |
| `line-4` | 开始读取权限 | `PERMISSION READ STARTED` | `lib/assets/line-4.mp3` | V5 (17.11–18.29s) | **1.18s** | 第四步（十六进制瀑布） |
| `line-5` | 读取完毕 · 核验通过 | `READ COMPLETE · VERIFIED` | `lib/assets/line-5.mp3` | V6 (19.71–21.41s) | **1.70s** | 第五步（环形准星扫描） |
| `line-6` | 欢迎 `<身份名称>` 访问 | `WELCOME, NAME` | `lib/assets/line-6.mp3` | **使用者自制，非原片** | **3.73s** | 终幕揭幕前，等它念完才揭幕 |

**V3（13.04–14.09s）是用户名字独白，按你的要求不使用。**

### 素材取不到时

`voiceSource = 'asset'`（默认）时优先用素材；**素材缺失或解码失败会自动回落到 TTS**
（`say` 字段就是回落用的文本）。设置页可强制 `tts`。

### 终幕的人声

原版 `line-6` 是从原片里截的「welcome」一声，实测只有 **0.34s**，是全片最短的一条，
收尾听着像被掐断。

**1.1.1** 曾临时用 `Microsoft Zira Desktop` 合成一句英文落幕词顶上去。
**1.1.2 起换成使用者自己重做的素材**：3.70s、40000 Hz / 立体声 / 16 bit 的 WAV，
由 `tools/wav2mp3.ps1` 转成 192 kbps MP3。

入库前做了两处处理（脚本 `tools/normalize-user-line6.py`）：

1. **修 RIFF 头**。来件是 ffmpeg 管道输出，`RIFF` / `data` 的长度字段都是
   `0xFFFFFFFF`，合规解析器会读成 26843 秒的假时长。脚本按块遍历、
   以实际字节数收尾，重写成尺寸正确的 WAV。
2. **电平对齐 +2.4 dB**。来件活跃段 RMS −25.0 dBFS，而五句真声是
   −22.3 ～ −22.9 dBFS（中位 −22.6）。播放端所有素材共用同一个增益，
   不对齐终幕会明显发虚。对齐后峰值 −9.0 dBFS，不削顶。

回解验证（MP3 → PCM 再量）：**时长 3.73s、峰值 −9.0 dBFS、
活跃段 RMS −22.9 dB**，与真声中位只差 0.4 dB。

各素材实测电平（Media Foundation 解回 PCM 量的；脚本
`tools/decode-to-wav.ps1` + `tools/decode-all.ps1`）：

| 素材 | 时长 | 峰值 | 活跃段 RMS |
|---|---|---|---|
| line-1 | 2.05s | −6.9 dBFS | −22.9 dB |
| line-2 | 1.24s | −4.9 dBFS | −22.3 dB |
| line-3 | 1.16s | −8.8 dBFS | −22.7 dB |
| line-4 | 1.27s | −5.9 dBFS | −22.6 dB |
| line-5 | 1.79s | −4.9 dBFS | −22.6 dB |
| **line-6** | **3.73s** | **−9.0 dBFS** | **−22.9 dB** |

揭幕的等待逻辑是 `await welcome`，所以**换长素材会自动把结尾撑开**，
不需要改动画时序。`finale()` 仍然只调 `voice.line(null, null, 'line-6')`，
不退回 TTS 念白（`test/smoke-splash.mjs` 第 8 节有回归断言钉住这条）。

### 素材缓存

Host 路由给素材设了 `Cache-Control: public, max-age=86400`。
换素材文件后浏览器会继续用旧的那份，所以 `splash.js` 的素材 URL 挂了
版本串破缓存：`/dsh-startup/asset/<name>.mp3?v=<插件版本>`。
查询串在 Host 侧取 basename 之前就被剥掉，不影响 `.mp3` 白名单校验。

---

## 二、界面音效 —— 8 个槽位

| # | 槽位 | 出声时机 | 素材 | 状态 |
|---|---|---|---|---|
| 1 | `cue` | **每次念台词之前**的两声轻提示 | 合成（1046.5 + 1568 Hz） | 合成 |
| 2 | `tick` | 文字逐字渐显 | `lib/assets/sfx-tick.mp3` | ✅ 真素材 |
| 3 | `step` | 每个阶段推进 | 同上 | ✅ 真素材 |
| 4 | `confirm` | 点按钮 / 按 Enter 确认 | 同上 | ✅ 真素材 |
| 5 | `tickRun` | 十六进制瀑布开始滚动 | `lib/assets/sfx-ticks-run.mp3` | ✅ 真素材 |
| 6 | `sweep` | 黑幕 → 暖白底板的洗白过场 | 合成（带通噪声扫频） | 合成 |
| 7 | `rise` | 黑幕上 DeepSeek 标识出现 | 合成（220→990 Hz 上行） | 合成 |
| 8 | `chime` | 终幕揭幕 | 合成（三音和声钟） | 合成 |

`tick` / `step` / `confirm` 目前**共用同一个「哒」**（音量不同）。
如果想让它们各用不同音效，补素材即可。

### 为什么 4 个还是合成

你给的音频里 **0–6.90s 是纯静音**：

- `rise` 对应原片约 3.9–5.5s → **原音频那里没有声音**
- `sweep` 对应原片约 6.2–6.7s → **同上**
- `chime` 对应 22.62–27.40s，但那是**配乐**不是音效

---

## 三、素材清单

```
lib/assets/
├─ line-1.mp3          40.3 KB   V1  需要访问许可
├─ line-2.mp3          24.5 KB   V2  身份资料确认
├─ line-3.mp3          23.0 KB   V4  接收访问需求
├─ line-4.mp3          25.0 KB   V5  开始读取权限
├─ line-5.mp3          35.2 KB   V6  读取完毕 · 核验通过
├─ line-6.mp3          88.2 KB   使用者自制  终幕落幕词（1.1.2 起）
├─ sfx-tick.mp3         2.1 KB   单声「哒」（20ms，质心 7.5kHz）
├─ sfx-ticks-run.mp3   10.2 KB   整串 10 个「哒」，每 45ms 一个
└─ bgm.mp3              3.4 MB   In Cyberpunk（Alex Chernykh）150.5s（1.2.0 起）
```

Host 经 `/dsh-startup/asset/<文件名>` 只读下发（正则白名单 + 防目录穿越）。
6 段真声素材的 40–120Hz 能量都在 −25 ~ −34 dB（片尾配乐是 −1.3 dB），
**素材本身干净，没有配乐底**。

---

## 四、时长怎么定

**不再写死。** 每一步的停留时间 = `max(视觉基准, 实际音频时长 + 240ms 收尾)`：

```js
var spoke = voice.line(step.say, step.zh, step.audio)   // Promise<这一句实际播了多久>
function holdFor(spoken) {
  var target = Math.max(ms(step.hold), (spoken || 0) + ms(240))
  return wait(Math.max(0, target - (spoken || 0)))
}
```

素材播多长，动画就等多久；**用户点得快也不掐断语音**。
只有「跳过 / 揭幕」才真的 `cancel()`。

按素材时长，五步的语音段落约：
`1.96s → 1.16s → 1.07s → 1.18s → 1.70s`（另加每次 240ms 的开头留白）。

---

## 五、有字但故意不配音的字段

`en`（中央大字）· `log` / `logEn`（底部日志）· `btnZh` / `btnEn`（按钮）· `badge`（阶段计数）·
`brand1/2/3`、`orgZh/orgEn/orgSub`、`welcomeBox`、`footer`（品牌与页脚）

---

## 六、相关设置项

| 设置项 | 作用 |
|---|---|
| `voice` | 语音播报总开关 |
| `voiceSource` | `asset`=优先真声素材 / `tts`=全 TTS |
| `voiceLang` | `en` / `zh` / `both`（只影响 TTS 回落时念什么） |
| `voiceName` / `voiceRate` / `voicePitch` / `voiceVolume` | TTS 音色与语调 |
| `voiceCue` | 念台词前的提示音开关 |
| `voiceLead` | 提示音之后留多久再开口（默认 240ms） |
| `sound` / `soundVolume` | 界面音效总开关与音量（**不连坐语音素材**） |
| `sfx` | 音效来源：`audio`=真素材 / `synth`=全合成 |
| `bgm` | 背景音乐总开关（默认开） |
| `bgmVolume` | 音乐音量 0…1（默认 0.2 ≈ 混音 −32 dBFS） |
| `bgmDuck` | 台词出声时自动闪避（默认开，退到 35% ≈ −9 dB） |

---

## 七、背景音乐（1.2.0 新增）

单独一条轨，独立于 `sound`（界面音效）和 `voice`（台词）。

| 项 | 值 |
|---|---|
| 素材 | `lib/assets/bgm.mp3` — *In Cyberpunk* / Alex Chernykh |
| 时长 | 150.49 s（2:30.5），48 kHz 立体声源 |
| 编码 | 192 kbps MP3，3.4 MB |
| 播放 | HTMLAudio 元素，`loop = true`，揭幕时 900 ms 淡出后 `pause()` |
| 起播 | **动画第一帧**（脚本解析时立即 `play()`），不等任何点击 |
| 兜底 | 被自动播放策略拦下时自动复位，退回第一次用户手势再起 |

### 为什么不等用户手势

`autoplayPolicy` 由宿主决定，两边的默认值正好相反：

| 宿主 | 策略 | 表现 |
|---|---|---|
| DeepSeek Harness Desktop（Electron） | `no-user-gesture-required`（**Electron 的默认值**，DSH 未覆盖） | 黑幕第一帧就有音乐 |
| `dsh web`（真实浏览器） | `document-user-activation-required`（Chromium 默认） | `play()` 被拒 → 退回第一次点击 |

所以代码是「**先试，失败再退**」：`bgm.start()` 在模块初始化时直接调用；
`play()` 的 Promise 被拒时把 `started` 复位、清掉斜坡定时器、音量归零，
等 `unlock()`（第一次 pointerdown / keydown / touchstart）再试一次。
两条路都不用判断宿主类型。

Electron 这一步的结论取自官方文档 `WebPreferences.autoplayPolicy`：
"Defaults to `no-user-gesture-required`"；并且 DSH 的 Electron 主进程
（`app.asar/lib/main.js`）与 `@deepseek-ai` 下 1381 个文件里都没有出现
`autoplayPolicy`，即未被覆盖。

### 为什么用 HTMLAudio 元素，而不是 WebAudio 解码

现有素材走 `fetch` + `decodeAudioData` 缓存进 `AudioBuffer`。BGM 有 2 分半，
解成 AudioBuffer 要占约 **57 MB** 内存；元素流式播放只占几百 KB，而且自带
`loop` —— 用户在前面几步磨蹭多久都不会断。音量用 30 ms 小步手动走斜坡：
闪避只要 200 ms 级就够，不值得为它引入 `MediaElementSource`（那条路一旦接错
就是静音，远程极难排查）。

### 电平：为什么必须重新归一

`In Cyberpunk` 是流媒体母带，**峰值顶在 0.0 dBFS、活跃 RMS −9.2 dBFS**，
而五句台词是 −22.6 dBFS —— 它比台词响 **13.4 dB**。直接进混音会把五句播报
全部盖住。所以入库前先归一到 **−18 dBFS 活跃 RMS**（脚本
`tools/normalize-bgm.py`），再由播放端乘一个很小的 `bgmVolume`：

| 环节 | 电平 |
|---|---|
| 原母带 | 峰值 0.0 dBFS / 活跃 RMS −9.2 dB |
| 归一后（入库） | 峰值 −9.2 dBFS / 活跃 RMS −18.0 dB |
| `bgmVolume = 0.2` 播放时 | 约 −32 dBFS |
| 台词出声、闪避生效 | 约 −41 dBFS（台词 −22.6 dB，低于台词 18 dB） |

### 闪避（ducking）

| 时机 | 动作 | 斜坡 |
|---|---|---|
| 真声素材开播前（`line()`） | `bgm.duck(true)` | 220 ms |
| 素材播完 | `bgm.duck(false)` | 600 ms |
| TTS 开口前（`ttsLine`） | `bgm.duck(true)` | 220 ms |
| TTS `settle()` | `bgm.duck(false)` | 600 ms |
| 揭幕「镜头后撤」起（`finale()`） | `bgm.stop(1700)` | 1700 ms 淡出 |
| 跳过（Esc / SKIP，`finish()`） | `bgm.stop(900)` | 900 ms 淡出 |

`stop()` 幂等：正常揭幕时 `finale()` 已经起过 1700 ms 的淡出，`finish()` 里那句
只服务跳过路径，不会重启斜坡。

`duck()` 在 `finished` 或 `stopping` 后直接返回，否则揭幕的淡出会被随后到达的
「闪避结束」抬回去。

### 1.2.1 的"音乐秒断"是怎么来的

**症状**：动画结束进入主界面时，音乐不是淡出，而是"啪"地一下断掉。

**根因**：`finish()` 第一句就是 `finished = true`，而音量斜坡的定时器当时写的是

```js
if (!el || finished) { clearInterval(timer); timer = null; return }   // ← 错
```

于是 `bgm.stop(900)` 刚把目标音量设成 0，斜坡就被自己的 `finished` 掐断，
音量停在原处；紧接着 `setTimeout` 到点 `pause()` —— **硬切**。

**修法**（1.2.2）：斜坡的守卫换成 bgm 自己的 `stopping` 标志，
只在「要往上抬」时拒绝；向下淡出永远允许走完。另外把淡出起点从 `finish()`
提前到 `finale()` 加 `dsu-handoff` 的那一刻，时长也从 900 ms 拉到 1700 ms，
正好盖住 780 ms 的镜头后撤 + 900 ms 的整体移出。

**另一个顺手补的洞**：设置页点「立即预览」会重新注入 `splash.js`，那是一份
全新的模块实例；旧实例的 `audio` 元素挂在旧闭包里，不叫停就会和新的一轨叠着放。
现在 `injectSelf()` 开头会先 `bgm.stop(0)` + `voice.stop()`。

### 已知边界

- **桌面端从黑幕第一帧就有音乐**（Electron 默认宽松）。**`dsh web` 下则要等
  第一次点击** —— Chromium 的默认策略会拒掉 `play()`，插件退回手势路径。
  这是宿主策略差异，不是插件行为不一致。
- 音乐是循环的：正常 15–25 秒内走完，听不到循环点；用户长时间停在某一步
  才会绕回开头。
- 起播那一刻会做 900 ms 淡入，避免黑幕里突然砸出一个满音量的和弦。
