# 1.6.0 优化说明：文字清晰度与活体光场

> 交付物：`releases/dsh-startup-screen-1.6.0.tgz`　截图证据：`_shots_1600_v1/`
> 改动前源码备份：`_backup/1.5.0-before-1.6.0/`

## 一、问题与根因

用户反馈三条：截图不够高级、字体发虚/不平滑、过程背景是静态的。

大字发虚的根因不是字号，而是三件事叠加：

1. 逐字入场动画结束后仍保留 `filter` 合成层，浏览器继续按合成层栅格化，中文笔画边缘发灰。
2. 主标题用 300 字重，Windows 上中文细笔画落到灰度抗锯齿，屏幕上看就是"毛边"。
3. `text-rendering: geometricPrecision` 在中文小字、大字上都不划算，反而破坏字形提示。

## 二、文字改造

- 逐字动画只保留位移与透明度，收尾显式 `filter: none !important`，不再残留合成层。
- 中文改用本机真实字体 `Noto Sans SC` 500 字重，`font-synthesis: none` 禁伪粗/伪斜。
- 主标题 48–72px、字距 0.135em；英文副标题 12.5px / 0.46em；根节点恢复默认平滑与排版提示。
- 标题中间的 `·` 单独橙色强调，给整句一个视觉锚，而不是一排平均字。

## 三、Canvas 活体光场

`package/lib/splash.js` 新增全屏 `<canvas class="dsu-field">`，夹在底板（z-index 11 前）与档案面板之间：

- 三层星尘：不同速度、不同亮度，中心区域按 `centerFade` 自动降亮，不压标题。
- 四条贝塞尔流光 + 沿光带移动的读取头，对应"正在读取"的叙事。
- 边缘数据雨、底部低频水线、横向扫描光带，填住上下留白。
- 暗色主题 `mix-blend-mode: screen`，浅色主题 `multiply`，两套都读得出运动。
- 设备像素比上限 1.75，避免 4K/高 DPR 下的填充率浪费。

## 四、生命周期与降级

- 揭幕、跳过、重播统一调用 `stopField()`，取消 RAF 与底部波形 90ms 计时器，不留后台空转。
- 无 Canvas / 无 `getContext` 直接跳过光场，动画其余部分照常。
- `prefers-reduced-motion: reduce` 只画一帧静态星图，不启动 RAF。

## 五、验证

- 四套冒烟测试 **352 项全过**：`smoke-host` 73、`smoke-splash` 194、`smoke-client` 40、`smoke-desktop-boot` 45。
- `smoke-splash` 第 [15] 节 16 条，覆盖 Canvas 挂载/层级/混合模式/DPR/降级/减动/读取头/星尘降亮/水线/波形/停止清理/颗粒抖动/500 字重/分隔点/面板尺寸/切角。
- 反向验证 3 类已知缺陷均能触发失败（退出码 1）：
  - 删掉 `<canvas class="dsu-field">` → `markup 挂载 Canvas 光场` 等 3 条红。
  - `filter: none !important` 改回 `blur(2px)` → `逐字入场不再用 blur 滤镜` 等红。
  - 500 字重改回 300 → `中文用真实 500 字重且禁伪粗` 红。
- 截图（1600×1000，Edge 无头）：稳定暗色 `_shots_1600_v1/dark-10000-d.png`、稳定浅色 `light-10000-d.png`；右侧自检面板 `LIVE` 完整显示（此前被右上切角裁成 `LIV`，已改为内联橙色状态字）。
- 动态证据：同一步 10000ms / 10250ms 两帧，排除标题区后背景差分均值 1.91/255、RMS 11.85/255；差异图 `diff-bg-x6.png`。

## 六、未验证的假设

- **未在真实 Electron 桌面端逐帧验证**：只验证了 Edge 无头渲染的静态帧与两帧差分，桌面端的合成器、字体回退、DPR 缩放可能有差异。
- `Noto Sans SC` 依赖本机已安装；目标机缺少时回退到 `PingFang SC` / `Microsoft YaHei`，字重会变，清晰度结论不自动成立。
- 假设 DPR 上限 1.75 在 4K 屏上仍够锐利，未在真实 4K/150% 缩放下目视核对。
- Canvas 常驻 RAF 的 GPU 占用与笔记本功耗未实测，只在无头环境确认无报错。

## 七、回滚

1. 源码回滚：用 `_backup/1.5.0-before-1.6.0/` 覆盖 `package/`。
2. 装机回滚：`dsh plugin --profile desktop add releases/dsh-startup-screen-1.5.0.tgz`（若旧包仍在 `releases/`）。
3. 版本号同步点：`package/package.json` 与 `package/lib/client.js` 的 `FALLBACK_VERSION`。
