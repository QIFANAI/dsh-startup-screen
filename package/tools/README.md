# tools/ —— 素材与版式工具（不参与 npm 打包）

`package.json` 的 `files` 只收 `lib` / `test` / `preview`，本目录**不会进 tgz**，
纯粹是开发与核对用的脚本，随源码副本一起留着。

---

## 一、音频

| 脚本 | 干什么 |
|---|---|
| `decode-to-wav.ps1` | 用 Media Foundation 把任意可解码音频（mp3 / m4a / …）转成 16-bit PCM WAV，用来**离线量电平** |
| `decode-all.ps1` | 把 `lib/assets/line-*.mp3` 全解一遍到 `_decoded/`，供对比 |
| `wav2mp3.ps1` | WAV → 192 kbps MP3（本机没有 ffmpeg / lame，走 MediaTranscoder） |
| `normalize-user-line6.py` | 修 ffmpeg 流式 WAV 的 `0xFFFFFFFF` 长度字段 + 把 line-6 电平对齐到真声中位 |
| `normalize-bgm.py` | 把 BGM 母带压到 −18 dBFS 活跃 RMS 再入库 |
| `make-voice*.ps1` | 早期用 SAPI 合成候选台词（1.1.1 用过，现已换成使用者自制素材） |

**为什么要解码再量**：MP3 的字节统计测不出响度（那只是压缩流特征）。
所有电平结论都必须先把素材解回 PCM。实测基准见 `AUDIO-FIELDS.md`。

`decode-to-wav.ps1` / `wav2mp3.ps1` 只能在 **Windows PowerShell 5.1**（`powershell.exe`）
下跑：PowerShell 7 已经没有 WinRT 投影，`MediaTranscoder` 用不了。
转换是异步的，`IAsyncAction` 交回来是个裸 COM 对象、`AsTask` 重载解析不了，
所以脚本改成"点火后轮询输出文件大小直到不再增长"。

---

## 二、版式（`layout-fixture.html`）

复刻启动动画的挂载结构，直接加载**真实的** `lib/splash.css` + `lib/splash.js`，
没有预览页那层控制台遮挡，专供无头截图核对版式。

```bash
EDGE="/c/Program Files (x86)/Microsoft/Edge/Application/msedge.exe"
BASE="file:///<本仓库绝对路径>/package/tools/layout-fixture.html"

"$EDGE" --headless=new --disable-gpu --no-sandbox --hide-scrollbars \
  --force-device-scale-factor=1 --window-size=1600,1020 \
  --virtual-time-budget=9000 \
  --screenshot=".../shot.png" "$BASE?theme=dark"
```

- `?theme=light|dark` 切换主题（默认 dark）。**两套都要看** ——
  1.2.2 的第一版拉丝纹理就是只在浅色底板上暴露成"灯芯绒"的。
- `--virtual-time-budget` 会把定时器快进，用来抓动画的任意时刻。
  **它是不可靠的**：同一时间戳两次运行可能落在不同帧（一次是稳定的第 5 步，
  一次停在过渡中间）。要多抓几个时间点挑稳定帧，别拿过渡帧下结论。

### 这个流程抓到过什么

1.2.2 改版时，1px 硬边 `repeating-linear-gradient` 做"金属拉丝"，
在暗色截图上看着还行，**在浅色截图上整片背景变成竖向罗纹布**。
靠肉眼看代码是发现不了的 —— 所以版式改动一律先截图再下结论。

---

## 三、清理

`_shots/`、`_decoded/`、`_bgm/`、`final-voice/` 都是中间产物，随时可删。
再生成本很低（每个截图约 12 秒，音频转码秒级）。
`final-voice/line-6.original-backup.mp3` 是上游原素材备份，**别删**。
