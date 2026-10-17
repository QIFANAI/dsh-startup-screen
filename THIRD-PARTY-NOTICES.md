# 第三方素材与商标说明

本仓库的**代码**以 MIT 许可发布。但启动动画里用到的部分影音素材来自第三方，
不具备再分发条件，因此**不随仓库提供**。下面逐项说明来源、处理方式与替代方案。

## 一、不随仓库分发的素材

| 文件 | 来源 | 处理 |
|---|---|---|
| `package/lib/assets/line-1.mp3` ~ `line-5.mp3` | 从 DeepSeek 官方宣传片截取的台词 | 不入库；缺失时自动回落浏览器 TTS 念白 |
| `package/lib/assets/sfx-tick.mp3`、`sfx-ticks-run.mp3` | 同一段官方宣传片截取的界面音效 | 不入库；缺失时自动回落到 WebAudio 合成音 |
| `package/lib/assets/bgm.mp3` | *In Cyberpunk* / Alex Chernykh（商业曲目） | 不入库；请自行放入你有权使用的音乐 |
| `package/tools/final-voice/` | 原始录音与降噪工程文件 | 不入库（含个人声音素材） |
| `package/tools/reference/`、`package/tools/_bgm/` | 开发期参照截图与母带 | 不入库 |

放置自有素材的方法见 `package/lib/assets/README.md`。文件名与格式保持不变即可，
代码会优先用素材、失败再回落合成音 / TTS。

## 一之二、随仓库分发的自制素材

| 文件 | 来源 | 授权 |
|---|---|---|
| `package/lib/assets/line-6.mp3` | 仓库作者本人录制的终幕欢迎语 | 作者保留著作权，授权随本项目自由使用、修改与再分发（与代码同一 MIT 条款） |

如果你再分发本项目，请保留本文件与该声明；若只想用代码，可整体替换或删除它，
插件会自动回落到 TTS。

## 二、商标与从属关系

- “DeepSeek”“深度求索”及鲸鱼标识是深度求索公司的商标/标识，
  本项目中仅用于**界面还原与学习交流**，不代表官方，也未获得官方背书。
- 本项目是社区插件，与 DeepSeek / DeepSeek Harness 官方无隶属关系。
- 若权利人认为使用不当，请开 Issue，我会在第一时间移除相关图形资源。

## 三、上游代码

- 原始插件 `dsh-startup-screen` 由沈宏宏以 MIT 许可发布，本仓库在其 1.1.0
  基础上修改而来，保留原始版权声明（见 `LICENSE`）。
- 上游若另有仓库地址，欢迎补充到 README 的 Credits 一节。

## 四、字体

- 界面中文优先使用系统已安装的 `Noto Sans SC`，其次回退 `PingFang SC` /
  `Microsoft YaHei`。仓库不打包任何字体文件。
