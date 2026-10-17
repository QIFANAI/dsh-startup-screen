/* ============================================================================
 * 启动动画初始化冒烟测试 —— 用最小 DOM 桩把 splash.js 完整跑一遍
 *
 * 为什么需要它：黑幕兜底是"贴在第一屏上的"，一旦 splash.js 初始化抛异常，
 * dsu-boot 就永远摘不掉 → 用户看到永久黑屏。这个测试专门守住那条线：
 *   1) 初始化不许抛异常
 *   2) 跑完必须摘掉 dsu-boot（否则就是黑屏）
 *   3) 暴露 __DSH_STARTUP_API__
 *   4) JS 里用到的每个选择器，都必须在生成出来的 markup 里真实存在
 *      —— 这条能抓到"接了个不存在的元素"这类手误
 *   5) 没有 speechSynthesis 的环境（Node / 老浏览器）也必须能跑
 *
 * 用法：node test/smoke-splash.mjs
 * ========================================================================== */
import fs from 'node:fs'
import vm from 'node:vm'
import { fileURLToPath } from 'node:url'

const BUNDLE = fileURLToPath(new URL('../lib/splash.js', import.meta.url))
const CSS = fileURLToPath(new URL('../lib/splash.css', import.meta.url))

let pass = 0
let fail = 0
function check(label, ok, extra) {
  if (ok) { pass++; console.log('  ok   ' + label) }
  else { fail++; console.log('  FAIL ' + label + (extra !== undefined ? '  → ' + extra : '')) }
}

/* ── 最小 DOM 桩 ─────────────────────────────────────────────────────────── */
function makeEl(tag) {
  const el = {
    tagName: tag,
    _cls: '',
    _text: '',
    _html: '',
    style: { setProperty() {}, removeProperty() {} },
    dataset: {},
    children: [],
    hidden: false,
    offsetWidth: 1,
    parentNode: null,
    appendChild(c) { this.children.push(c); if (c) c.parentNode = this; return c },
    insertBefore(c) { this.children.unshift(c); if (c) c.parentNode = this; return c },
    removeChild(c) { const i = this.children.indexOf(c); if (i >= 0) this.children.splice(i, 1); return c },
    setAttribute() {},
    getAttribute() { return null },
    addEventListener() {},
    removeEventListener() {},
    dispatchEvent() {},
    animate() { return { cancel() {}, finish() {} } },
    getTotalLength() { return 120 },
    querySelector(sel) { return lookup(sel) },
    querySelectorAll() { return [] },
    focus() {},
    contains() { return false },
  }
  Object.defineProperty(el, 'className', {
    get() { return el._cls },
    set(v) { el._cls = v == null ? '' : String(v) },
  })
  Object.defineProperty(el, 'textContent', {
    get() { return el._text },
    set(v) { el._text = v == null ? '' : String(v) },
  })
  Object.defineProperty(el, 'innerHTML', {
    get() { return el._html },
    set(v) { el._html = v == null ? '' : String(v); MARKUP = el._html },
  })
  el.classList = {
    add(...cs) { cs.forEach((c) => { if (!el._cls.split(' ').includes(c)) el._cls = (el._cls + ' ' + c).trim() }) },
    remove(...cs) { cs.forEach((c) => { el._cls = el._cls.split(' ').filter((x) => x && x !== c).join(' ') }) },
    toggle(c, on) {
      const has = el._cls.split(' ').includes(c)
      const want = on === undefined ? !has : !!on
      if (want && !has) el.classList.add(c)
      if (!want && has) el.classList.remove(c)
    },
    contains(c) { return el._cls.split(' ').includes(c) },
  }
  return el
}

/* markup 里出现过的 class 集合：选择器必须命中它，否则视为"接了个不存在的元素" */
let MARKUP = ''
const MISSED = new Set()
const lookupCache = new Map()
function lookup(sel) {
  if (!sel) return null
  const key = String(sel)
  if (lookupCache.has(key)) return lookupCache.get(key)
  const m = /\.([A-Za-z0-9_-]+)/.exec(key)
  const cls = m ? m[1] : null
  const found = cls !== null && MARKUP.includes(cls)
  if (!found) MISSED.add(key)
  const node = found ? makeEl('div') : null
  lookupCache.set(key, node)
  return node
}

/* ── window / document ───────────────────────────────────────────────────── */
const spoken = []
function makeSpeech() {
  return {
    /* 故意混入"老拼接合成"音色：David(男) / Zira(女) / Huihui(女)，
       正确的选择应该跳过它们，挑 Online (Natural) 那两个 */
    _voices: [
      { name: 'Microsoft David Desktop - English (United States)', lang: 'en-US', localService: true },
      { name: 'Microsoft Zira Desktop - English (United States)', lang: 'en-US', localService: true },
      { name: 'Microsoft Huihui Desktop - Chinese (Simplified)', lang: 'zh-CN', localService: true },
      { name: 'Microsoft Aria Online (Natural) - English (United States)', lang: 'en-US', localService: false },
      { name: 'Microsoft Xiaoxiao Online (Natural) - Chinese (Mainland)', lang: 'zh-CN', localService: false },
    ],
    getVoices() { return this._voices },
    speak(u) { spoken.push(u) },
    cancelCalls: 0,
    cancel() { this.cancelCalls++; spoken.length = 0 },
    resume() {},
    pause() {},
    addEventListener() {},
    removeEventListener() {},
  }
}

function run(withSpeech, cfgOverride) {
  MARKUP = ''
  MISSED.clear()
  lookupCache.clear()
  spoken.length = 0

  const root = makeEl('div')
  root._cls = 'dsu-root dsu-boot'
  const head = makeEl('head')
  const body = makeEl('body')
  const htmlEl = makeEl('html')

  const documentStub = {
    readyState: 'complete',
    head, body,
    documentElement: htmlEl,
    getElementById: (id) => (id === 'dsh-startup-root' ? root : null),
    createElement: (t) => makeEl(t),
    createElementNS: (_ns, t) => makeEl(t),
    querySelector: () => null,
    addEventListener() {},
    removeEventListener() {},
  }

  const timers = []
  const windowStub = {
    __DSH_STARTUP__: {
      enabled: true, mode: 'always', theme: 'light', speed: 1,
      requireInteraction: true, allowSkip: true,
      identity: 'JOYCE MOORE', identityId: '0087', accessLevel: '3',
      /* 只覆盖测试要变的；语速/音调/留白故意留空，好让断言直接校验 splash.js 出厂默认值 */
      voice: true, voiceLang: 'en', voiceName: '',
      sound: true, soundVolume: 0.5,
    },
    AudioContext: function () {
      return {
        state: 'running', currentTime: 0, sampleRate: 48000, destination: {},
        resume() {},
        createOscillator() {
          return { type: '', frequency: { setValueAtTime() {}, exponentialRampToValueAtTime() {} }, connect() {}, start() {}, stop() {} }
        },
        createGain() {
          return { gain: { value: 0, setValueAtTime() {}, exponentialRampToValueAtTime() {} }, connect() {} }
        },
        createBuffer(ch, len) { return { getChannelData: () => new Float32Array(len) } },
        createBufferSource() { return { buffer: null, connect() {}, start() {} } },
        createBiquadFilter() { return { type: '', frequency: { value: 0 }, Q: { value: 0 }, connect() {} } },
      }
    },
    location: { host: '127.0.0.1:3080', href: 'http://127.0.0.1:3080/' },
    addEventListener() {}, removeEventListener() {}, dispatchEvent() {},
    sessionStorage: { getItem: () => null, setItem() {} },
    localStorage: { getItem: () => null, setItem() {} },
    requestAnimationFrame: (fn) => { fn(); return 1 },
    cancelAnimationFrame() {},
    /* 小延时同步执行 —— voiceLead 是 240ms，不这样做 line() 永远开不了口；
       大延时（动画时间线）照旧入队，测试保持同步可控 */
    setTimeout: (fn, ms) => {
      if ((ms || 0) <= 400) { fn(); return -1 }
      timers.push({ fn, ms })
      return timers.length
    },
    clearTimeout() {},
    setInterval: () => 1,
    clearInterval() {},
    CustomEvent: function (t) { this.type = t },
  }
  if (withSpeech) {
    windowStub.speechSynthesis = makeSpeech()
    /* 浏览器里 window === globalThis，但沙箱里是两回事：
       splash.js 检查的是 window.SpeechSynthesisUtterance，所以两边都要挂 */
    windowStub.SpeechSynthesisUtterance = function (t) {
      this.text = t; this.rate = 1; this.pitch = 1; this.volume = 1
    }
  }
  windowStub.window = windowStub

  const sandbox = {
    window: windowStub,
    document: documentStub,
    console,
    Promise, Object, Array, JSON, String, Number, Math, Date, Error, RegExp, isFinite,
    setTimeout: windowStub.setTimeout,
    clearTimeout: windowStub.clearTimeout,
    setInterval: windowStub.setInterval,
    clearInterval: windowStub.clearInterval,
    requestAnimationFrame: windowStub.requestAnimationFrame,
    SpeechSynthesisUtterance: withSpeech
      ? function (t) { this.text = t; this.rate = 1; this.pitch = 1; this.volume = 1 }
      : undefined,
  }
  sandbox.globalThis = sandbox
  sandbox.self = sandbox

  /* 配置覆盖必须在跑脚本之前生效 —— splash.js 只在加载时读一次配置 */
  Object.assign(windowStub.__DSH_STARTUP__, cfgOverride || {})

  vm.createContext(sandbox)
  const src = fs.readFileSync(BUNDLE, 'utf8')
  let thrown = null
  try {
    vm.runInContext(src, sandbox, { filename: 'splash.js' })
  } catch (e) {
    thrown = e
  }
  return { windowStub, root, head, timers, thrown, markup: MARKUP, sandbox, spoken }
}

/* ── 开跑 ───────────────────────────────────────────────────────────────── */
console.log('\n[1] 有 speechSynthesis 的环境（Chrome / Edge）')
let r = run(true)
check('初始化不抛异常', r.thrown === null, r.thrown && (r.thrown.message + '\n       ' + String(r.thrown.stack).split('\n')[1]))
check('摘掉了黑幕 dsu-boot（没摘掉 = 永久黑屏）', !r.root.classList.contains('dsu-boot'), '当前 class = ' + r.root._cls)
check('暴露了 __DSH_STARTUP_API__', !!(r.windowStub.__DSH_STARTUP_API__ && r.windowStub.__DSH_STARTUP_API__.replay))
check('API 上有 replay / skip / finish', ['replay', 'skip', 'finish'].every((k) => typeof (r.windowStub.__DSH_STARTUP_API__ || {})[k] === 'function'))
check('没有 FAILED 兜底标记', r.windowStub.__DSH_STARTUP_FAILED__ !== true)

console.log('\n[2] 生成出来的 markup 完整性')
for (const cls of [
  'dsu-plate', 'dsu-vignette', 'dsu-black-inner', 'dsu-wash', 'dsu-brand-1', 'dsu-frame',
  'dsu-scanline', 'dsu-corner', 'dsu-slats', 'dsu-voice', 'dsu-meta', 'dsu-status-zh',
  'dsu-sub-en', 'dsu-rule', 'dsu-logo', 'dsu-dots', 'dsu-idline', 'dsu-reticle', 'dsu-hex',
  'dsu-welcome', 'dsu-w1', 'dsu-btn', 'dsu-card', 'dsu-skip', 'dsu-foot', 'dsu-sub-zh',
  'dsu-progress', 'dsu-bloom', 'dsu-streak', 'dsu-flash',
  /* 1.5.0 候选新增层 */
  'dsu-atmo', 'dsu-field', 'dsu-beams', 'dsu-floor', 'dsu-trace', 'dsu-checks',
]) {
  check('markup 含 .' + cls, r.markup.includes(cls))
}

console.log('\n[3] JS 用到的每个选择器都真实存在')
check('没有落空的选择器', MISSED.size === 0, [...MISSED].join(', '))

console.log('\n[4] 没有 speechSynthesis 的环境（老浏览器 / 隐私模式）')
r = run(false)
check('初始化不抛异常', r.thrown === null, r.thrown && r.thrown.message)
check('照样摘掉黑幕', !r.root.classList.contains('dsu-boot'), '当前 class = ' + r.root._cls)
check('暴露了 API', !!r.windowStub.__DSH_STARTUP_API__)

console.log('\n[5] 音色挑选：必须跳过拼接合成音色，挑神经网络女声')
r = run(true)
let api = r.windowStub.__DSH_STARTUP_API__
check('默认 voiceName 留空 = 自动挑', api.config.voiceName === '')
api.speak('Access permission required.')
let u = r.spoken[r.spoken.length - 1]
let vname = u && u.voice ? u.voice.name : '(未设置 voice)'
check('英文挑到 Aria Online (Natural)，而不是 David/Zira', /aria/i.test(vname) && /natural|online/i.test(vname), vname)
check('不是男声 David', !/david/i.test(vname), vname)

r = run(true, { voiceLang: 'zh' })
api = r.windowStub.__DSH_STARTUP_API__
api.speak('Access permission required.', '需要访问许可')
u = r.spoken[r.spoken.length - 1]
vname = u && u.voice ? u.voice.name : '(未设置 voice)'
check('中文挑到 Xiaoxiao Online (Natural)，而不是 Huihui', /xiaoxiao/i.test(vname) && /natural|online/i.test(vname), vname)

r = run(true, { voiceLang: 'both' })
api = r.windowStub.__DSH_STARTUP_API__
api.speak('Verification passed.', '验证通过')
const names = r.spoken.map((x) => (x.voice ? x.voice.name : '')).filter(Boolean)
check('中英各念一遍 = 排了两条 utterance', r.spoken.length === 2, String(r.spoken.length))
check('中文用中文音色、英文用英文音色', names.some((n) => /xiaoxiao/i.test(n)) && names.some((n) => /aria/i.test(n)), names.join(' | '))

console.log('\n[6] 播报语调节奏与名字念法')
r = run(true)
api = r.windowStub.__DSH_STARTUP_API__
api.speak('Identity verification.')
u = r.spoken[r.spoken.length - 1]
check('语速落在电影旁白档（0.8–0.95，比朗读慢）', u.rate >= 0.8 && u.rate <= 0.95, String(u.rate))
check('音调压低（0.78–0.92，深沉）', u.pitch >= 0.78 && u.pitch <= 0.92, String(u.pitch))
check('名字全大写会转 Title Case（避免逐字母念）', api.speakName('JOYCE MOORE') === 'Joyce Moore', api.speakName('JOYCE MOORE'))
check('中文名字原样不动', api.speakName('琉璃') === '琉璃', api.speakName('琉璃'))
check('API 暴露了 voice 供设置页显示', typeof api.voice === 'string')

console.log('\n[7] 动画不许掐断语音（这是这一版的核心诉求）')
r = run(true)
api = r.windowStub.__DSH_STARTUP_API__
const speech = r.windowStub.speechSynthesis
check('voiceLead 默认 240ms（提示音后留一拍再开口）', api.config.voiceLead === 240, String(api.config.voiceLead))
speech.cancelCalls = 0
api.speak('Access permission required.')
api.speak('Identity verification.')
api.speak('Access request received.')
check('连播三句，cancel 一次都没调用（队列顺序播报）', speech.cancelCalls === 0, 'cancel ' + speech.cancelCalls + ' 次')
check('三句都排进了队列', r.spoken.length === 3, String(r.spoken.length))
speech.cancelCalls = 0
api.skip()
check('按跳过时才真的掐断（cancel 1 次）', speech.cancelCalls === 1, 'cancel ' + speech.cancelCalls + ' 次')

console.log('\n[8] 终幕用真声欢迎语（来自 Video Project 3 的 line-6）')
{
  const src = fs.readFileSync(BUNDLE, 'utf8')
  check('全程没有 voice.tts( 调用（不再用 TTS 念白）', !/voice\.tts\(/.test(src))
  check('终幕挂了 line-6 素材', /voice\.line\(null, null, 'line-6'\)/.test(src))
  check('揭幕前会等欢迎语播完', /\.then\(function \(\) \{ return welcome \}\)/.test(src))
  check('预加载包含 line-6', /ensureAsset\('line-6'\)/.test(src))
  check('五步仍然各自挂着真声素材', (src.match(/audio: 'line-/g) || []).length === 5)
  check('总共 6 份人声素材被引用', (src.match(/'line-[1-6]'/g) || []).length >= 6)
}

console.log('\n[9] 背景音乐轨（1.2.0 新增 / 1.2.1 改为一开场即播）')
{
  const src = fs.readFileSync(BUNDLE, 'utf8')
  check('素材 URL 挂版本串（破 24h 强缓存）', /asset\/' \+ name \+ '\.mp3\?v=' \+ ASSET_V/.test(src))
  check('bgm 走 HTMLAudio 元素而不是 decodeAudioData', /document\.createElement\('audio'\)/.test(src))
  check('bgm 元素循环播放（用户磨蹭多久都不怕断）', /el\.loop = true/.test(src))
  check('bgm 素材名固定为 bgm', /assetUrl\('bgm'\)/.test(src))
  check('模块初始化就 prepare + 起播，不等任何点击', /bgm\.prepare\(\)\s*\n\s*bgm\.start\(\)/.test(src))
  check('自动播放被拦时复位，留给手势兜底重试', /started = false[\s\S]{0,320}el\.pause\(\)/.test(src))
  check('手势兜底仍在（web profile 用）', /voice\.unlock\(\)\s*\n\s*bgm\.start\(\)/.test(src))
  check('真声素材：播报前闪避一次', /bgm\.duck\(true\)[\s\S]{0,200}playAssetAndWait/.test(src))
  check('真声素材：播完收闪避', /playAssetAndWait[\s\S]{0,200}bgm\.duck\(false\)/.test(src))
  check('TTS 路径：开口前闪避', /saidOnce = true\s*\n\s*bgm\.duck\(true\)/.test(src))
  check('TTS 路径：settle 时收闪避', /bgm\.duck\(false\)\s*\n\s*setMeter\(false\)/.test(src))
  check('揭幕时淡出并停掉', /bgm\.stop\(900\)/.test(src))
  check('闪避退到 35%（约 −9 dB）', /base\(\) \* 0\.35/.test(src))
  check('揭幕/跳过后 duck 不再改音量（finished + stopping 双守卫）', /if \(!started \|\| failed \|\| !el \|\| finished \|\| stopping\) return/.test(src))
  check('起播失败静默降级（不抛给动画）', /typeof p\.catch === 'function'/.test(src))
}

console.log('\n[10] 1.2.2 版式与质感修正')
{
  const src = fs.readFileSync(BUNDLE, 'utf8')
  const css = fs.readFileSync(CSS, 'utf8')
  /* 反向断言（"不再……"）必须先剥掉注释：注释里会引用旧写法，
     否则断言会被自己的说明文字绊倒 —— 这本身就是一次错误的失败。 */
  const cssCode = css.replace(/\/\*[\s\S]*?\*\//g, '')

  /* ① ID 行原本落在 screen 中央偏右，正好压在中英状态行上 */
  check('ID 行不再挂在中央偏右（去掉 calc(50% + 190px)）', !/calc\(50% \+ 190px\)/.test(cssCode))
  check('ID 行归到左上信息栏', /\.dsu-idline \{[^}]*left: 46px/.test(cssCode))
  check('ID 编号用强调色点出', /\.dsu-idline b \{ color: var\(--dsu-accent\)/.test(cssCode))
  check('ID 行不再用 transform 做垂直居中', !/\.dsu-idline\.dsu-in \{ opacity: 1; transform: translateY\(-50%\)/.test(cssCode))
  check('ID 行由 el() 建节点（不依赖 createTextNode）', /ui\.idline\.appendChild\(el\('span'/.test(src))

  /* ② 准星半径 = 150/400 × 盒宽；56vw 时刚好等于最长状态字的半宽，会切字 */
  check('准星放大到 66vw（给状态字留净空）', /\.dsu-reticle \{[^}]*min\(66vw, 94vh, 1180px\)/.test(cssCode))
  check('状态字与副标题加了底板色护城河', /\.dsu-status,\n\.dsu-sub-en \{[^}]*text-shadow/.test(cssCode))

  /* ③ BGM 淡出被 finished 掐断 —— 1.2.1 实机"秒断"的根因 */
  check('淡出斜坡不再被 finished 掐断', /!el \|\| \(stopping && want > 0\)/.test(src))
  check('揭幕从"镜头后撤"起就淡出（1700ms）', /bgm\.stop\(1700\)/.test(src))
  check('stop() 幂等，跳过路径重复调用不重启淡出', /if \(!started \|\| !el \|\| stopping\) return/.test(src))

  /* ④ 质感层 */
  check('底板有拉丝纹理层', /--dsu-brush: url\("data:image\/svg\+xml/.test(cssCode))
  check('底板掠光不用 mix-blend-mode（不新建隔离层）', !/\.dsu-plate::after \{[^}]*mix-blend-mode/.test(cssCode))
  check('胶片颗粒提到 0.075', /\.dsu-grain \{[^}]*opacity: 0\.075/.test(cssCode))
  check('角标改为机加工定位角（22px）', /\.dsu-corner \{[^}]*width: 22px/.test(cssCode))
  check('进度条改为金属渐变', /\.dsu-progress i \{[^}]*linear-gradient\(180deg/.test(cssCode))
  check('橙色进度条单独给金属渐变', /\.dsu-progress\.dsu-accent i \{[^}]*linear-gradient/.test(cssCode))

  /* ⑤ 实机截图才发现的两处：规则条纹在浅底上读成灯芯绒；重播会叠两轨 BGM */
  check('拉丝不再用 1px 硬边（浅底会读成灯芯绒）', !/rgba\(255, 255, 255, 0\.022\) 0px/.test(cssCode))
  check('拉丝不再用规则条纹（1.3.1 起改随机 turbulence）', !/repeating-linear-gradient\(90deg,\s*rgba\(0, 0, 0, 0\) 0px/.test(cssCode))
  check('中文字面优先 Noto Sans SC / 思源黑体系', /--dsu-zh: "Noto Sans SC", "Source Han Sans SC"/.test(cssCode))
  check('重播时先收掉旧实例的 BGM（否则两轨叠放）', /try \{ bgm\.stop\(0\) \}/.test(src))
  check('重播时也掐掉旧实例的语音', /try \{ voice\.stop\(\) \}/.test(src))
}

console.log('\n[11] 1.3.0 批次 1：机械感动效')
{
  const src = fs.readFileSync(BUNDLE, 'utf8')
  const css = fs.readFileSync(CSS, 'utf8')
  const cssCode = css.replace(/\/\*[\s\S]*?\*\//g, '')

  /* A1 文字解码 */
  check('主字走解码模式', /typeIn\(ui\.statusZh, step\.zh, 46, 'decode'\)/.test(src))
  check('英文字幕也走解码', /typeIn\(ui\.subEn, step\.en, 13, 'decode'\)/.test(src))
  check('替身字形分全角 / 半角两组', /GLYPH_WIDE/.test(src) && /GLYPH_NARROW/.test(src))
  check('按目标字宽选字形池（保住居中不抖）', /charCodeAt\(0\) > 0x2e7f/.test(src))
  check('解码共用一个 interval，不是每字一个 timer', /var DECODE_TICK = 55/.test(src))
  check('releaseAll 会把未锁定的字强制锁定', /timers\.length = 0\s*\n\s*stopDecode\(\)/.test(src))

  /* A2 逐字入场：1.6.0 起不再对字形做 filter，避免合成层把中文抗锯齿压成灰度 */
  check('逐字入场不再用 blur 滤镜', !/\.dsu-status \.dsu-ch,[\s\S]{0,220}filter: blur\(2px\)/.test(cssCode))
  check('逐字收尾显式 filter:none（不残留合成层）', /\.dsu-status \.dsu-ch,[\s\S]{0,220}filter: none !important/.test(cssCode))

  /* A6 准星 */
  check('刻度环 48 格', /var TICKS = 48/.test(src))
  check('刻度沿环逐格点亮', /@keyframes dsu-tick-on/.test(cssCode))
  check('准星有雷达扫描扇区', /dsu-ret-scan/.test(src) && /\.dsu-ret-scan \{/.test(cssCode))
  check('扫描用 closest-side 锚半径（否则环带落到环外）', /circle closest-side at 50% 50%/.test(cssCode))
  check('扫描有环形遮罩，不盖中央文字', /mask-image: radial-gradient\(circle closest-side/.test(cssCode))
  check('准星出现时咬合', /@keyframes dsu-ret-lock/.test(cssCode) && /classList\.add\('dsu-lock'\)/.test(src))

  /* A8 故障升级 */
  check('色散位移改为收敛（1100ms steps(5)）', /1100ms steps\(5, end\) 1 both/.test(cssCode))
  check('不再用等幅抖两下', !/430ms steps\(3, end\) 2/.test(cssCode))
  check('新增屏幕撕裂带', /dsu-tear/.test(src) && /@keyframes dsu-tear/.test(cssCode))
  check('撕裂带用 transform 位移（不动 top）', /@keyframes dsu-tear \{[^}]*translate\(0, 6vh\)/.test(cssCode))
}

console.log('\n[12] 1.3.1 批次 2：质感')
{
  const src = fs.readFileSync(BUNDLE, 'utf8')
  const css = fs.readFileSync(CSS, 'utf8')
  const cssCode = css.replace(/\/\*[\s\S]*?\*\//g, '')

  /* B1 真实拉丝 —— 用随机 turbulence 取代规则条纹 */
  check('B1 拉丝用 feTurbulence 随机纹理', /baseFrequency='0\.82 0\.014'/.test(cssCode))
  check('B1 纹理 alpha 钉成 1（不透明灰噪，不是随机透明斑点）', /feFuncA type='linear' slope='0' intercept='1'/.test(cssCode))
  check('B1 噪声振幅压在 ±0.05（近黑底板对纹理极敏感）', /slope='0\.10' intercept='0\.45'/.test(cssCode))
  check('B1 用 background-blend-mode: overlay（不洗淡底板）', (cssCode.match(/background-blend-mode: overlay, normal, normal/g) || []).length === 2)
  check('B1 深浅两套主题都挂纹理层', (cssCode.match(/var\(--dsu-brush\)/g) || []).length === 2)

  /* B2 掠光扫过 */
  check('B2 新增掠光层 .dsu-sheen', /\.dsu-sheen \{/.test(cssCode))
  check('B2 掠光用 transform 位移（走合成层）', /@keyframes dsu-sheen \{/.test(cssCode) && /translateX\(232%\)/.test(cssCode))
  check('B2 掠光在洗白那一刻触发', /black\.style\.opacity = '0'[\s\S]{0,240}sheen\.classList\.add\('dsu-go'\)/.test(src))
  check('B2 暗色主题单独压过掠光强度', /\.dsu-dark \.dsu-sheen \{/.test(cssCode))

  /* B3 机箱倒角 */
  check('B3 底板外框闭合', /\.dsu-frame::before \{/.test(cssCode))
  check('B3 框是双层边（内高光 + 外投影）', /\.dsu-frame::before \{[^}]*inset 0 1px 0[^}]*0 1px 0/.test(cssCode))
  check('B3 框随 dsu-in 一起淡入', /\.dsu-frame\.dsu-in::before/.test(cssCode))

  /* B4 分层景深 */
  check('B4 水位面板加投影', /\.dsu-wm \{[^}]*box-shadow/.test(cssCode))
  check('B4 暗色主题投影更重', /\.dsu-dark \.dsu-wm \{[^}]*rgba\(0, 0, 0, 0\.55\)/.test(cssCode))

  /* B5 鲸鱼标识金属化 */
  check('B5 鲸鱼用金属渐变高光层', /dsu-metal-/.test(src) && /style\.fill = 'url\(#'/.test(src))
  check('B5 高光/阴影渐变，而不是把整个形状调半透明', /'#ffffff'/.test(src) && /'#000000'/.test(src) && /stop-opacity/.test(src))
  check('B5 本体实心底 + 叠加渐变层（两条同形状路径）', (src.match(/WHALE_PATH\)\s*\n/g) || []).length >= 2)

  /* B6 暗角 + 边缘色散 */
  check('B6 边缘色散（左冷右暖、贴边 38%）', /rgba\(41, 113, 184, 0\.045\) 0%/.test(cssCode) && /rgba\(255, 59, 48, 0\.045\) 0%/.test(cssCode))
  check('B6 浅色暗角加深到 0.12', /rgba\(0, 0, 0, 0\.12\) 100%/.test(cssCode))
  check('B6 暗色暗角加深到 0.46', /rgba\(0, 0, 0, 0\.46\) 100%/.test(cssCode))
}

console.log('\n[13] 1.4.0 批次 3：真实自检读数')
{
  const src = fs.readFileSync(BUNDLE, 'utf8')
  const css = fs.readFileSync(CSS, 'utf8')
  const cssCode = css.replace(/\/\*[\s\S]*?\*\//g, '')

  check('取不到事实时显示 "—" 而不是假数据', /function factText[\s\S]{0,160}'—'/.test(src))
  check('短指纹缺失时退回破折号', /function factHash\(\) \{ return F\.hash \? String\(F\.hash\) : '--------' \}/.test(src))
  check('REV 行改用真实版本 + profile', /'REV ' \+ factText\(F\.version\)/.test(src))
  /* 反向断言必须剥注释：注释里会提到旧写法，否则断言会被自己的说明文字绊倒 */
  const srcCode = src.replace(/\/\*[\s\S]*?\*\//g, '').replace(/^\s*\/\/.*$/gm, '')
  check('不再写死 "REV 0.1.0 · WEB PROFILE"', !/REV 0\.1\.0 · WEB PROFILE/.test(srcCode))
  check('MODEL 读数来自 F.model', /'· MODEL : '[\s\S]{0,90}factText\(F\.model\)/.test(src))
  check('SANDBOX 读数来自 F.sandbox', /'· SANDBOX : '[\s\S]{0,90}factText\(F\.sandbox\)/.test(src))
  check('BUNDLES 读数来自 F.bundleCount（不是 plugin entry 数）', /' · BUNDLES : '[\s\S]{0,300}factText\(F\.bundleCount\)/.test(src))
  check('自检行用真实的 插件/活跃/会话 数', /'系统自检中… 插件 ' \+ factText\(F\.plugins\)[\s\S]{0,120}factText\(F\.activePlugins\)/.test(src))
  check('终幕副标题带真实短指纹（首尾呼应）', /SESSION ' \+ factHash\(\)/.test(src))
  check('读数随 idline 一起显隐', /ui\.fact1\.classList\.add\('dsu-in'\)/.test(src) && /ui\.fact1\.classList\.remove\('dsu-in'\)/.test(src))
  check('CSS 有 .dsu-facts 定位与强调色', /\.dsu-facts \{/.test(cssCode) && /\.dsu-facts b \{ color: var\(--dsu-accent\)/.test(cssCode))
  check('两行读数不与 ID 行重叠（240 / 258）', /\.dsu-facts-1 \{ top: 240px; \}/.test(cssCode) && /\.dsu-facts-2 \{ top: 258px; \}/.test(cssCode))
}

console.log('\n[14] 1.5.0 候选：光学档案仪器层')
{
  const src = fs.readFileSync(BUNDLE, 'utf8')
  const css = fs.readFileSync(CSS, 'utf8')
  const cssCode = css.replace(/\/\*[\s\S]*?\*\//g, '')

  /* ── A 空间：大气层 / 体积光 / 地面 / 镜头推进 ── */
  check('A1 大气层两条反向漂移光团', /\.dsu-atmo::before[\s\S]{0,420}dsu-atmo-a/.test(cssCode) && /\.dsu-atmo::after[\s\S]{0,420}dsu-atmo-b/.test(cssCode))
  check('A2 体积光两道（前后景不同速）', /\.dsu-beams::before \{ left: 8%/.test(cssCode) && /\.dsu-beams::after \{[\s\S]{0,80}animation-duration: 19s/.test(cssCode))
  check('A2 体积光用 screen 混合（暗色）/ soft-light（浅色）', /mix-blend-mode: screen/.test(cssCode) && /not\(\.dsu-dark\) \.dsu-beams \{ mix-blend-mode: soft-light/.test(cssCode))
  check('A3 地面有 1px 地平线', /\.dsu-floor::after \{[\s\S]{0,320}height: 1px/.test(cssCode))
  check('A4 底板 1.035× / 档案面板 1.06× 视差', /\.dsu-cam \.dsu-plate \{ transform: scale\(1\.035\)/.test(cssCode) && /\.dsu-cam \.dsu-watermark \{ transform: scale\(1\.06\)/.test(cssCode))

  /* ── B 材质：内倒角 / 三层景深 / 刻度机框 ── */
  check('B1 底板内倒角 + 顶部环境光 + 底部压暗', /\.dsu-plate::before[\s\S]{0,340}inset 0 90px 140px/.test(cssCode) && /inset 0 -180px 220px/.test(cssCode))
  check('B2 档案面板远/中/近三层不同模糊', /\.dsu-wm-far \{ filter: blur\(2\.6px\)/.test(cssCode) && /\.dsu-wm-mid \{ filter: blur\(1\.1px\)/.test(cssCode) && /\.dsu-wm-near \{ filter: blur\(0\.3px\)/.test(cssCode))
  check('B3 机框收进 22px 并补顶部刻度尺', /\.dsu-frame::before \{\s*inset: 22px/.test(cssCode) && /repeating-linear-gradient\(90deg, var\(--dsu-hair\) 0 1px, transparent 1px 24px\)/.test(cssCode))

  /* ── C 字阶：标题成为主体，副标题降一档 ── */
  check('C1 主标题 48–72px 变量尺寸', /--dsu-title-size: clamp\(48px, 4\.7vw, 72px\)/.test(cssCode) && /font-size: var\(--dsu-title-size\)/.test(cssCode))
  check('C2 英文副标题 12.5px / 0.46em', /\.dsu-sub-en \{\s*margin-top: 16px;\s*font-size: 12\.5px;[\s\S]{0,120}letter-spacing: 0\.46em/.test(cssCode))

  /* ── D 准星：精密环 / 彗星 / 冲击波 ── */
  check('D1 外环收成 1.6px 精密环', /\.dsu-reticle \.dsu-ring-a \{ stroke-width: 1\.6;/.test(cssCode))
  check('D2 彗星弧 6.8s 独立转速', /\.dsu-ret-comet \{[\s\S]{0,360}animation: dsu-spin 6\.8s linear infinite/.test(cssCode))
  check('D3 冲击波只在 dsu-lock 时触发', /\.dsu-reticle\.dsu-lock \.dsu-ping \{ animation: dsu-ping/.test(cssCode))

  /* ── E 逻辑：清单 / 瀑布 / 轨迹全部接真实 facts ── */
  check('E1 自检清单五项接 collectFacts 字段', /\['PROFILE', F\.profile\][\s\S]{0,220}F\.sessions/.test(src))
  check('E2 第 n 步点亮第 n 项，前项转已读态', /function setChecks\(active\)[\s\S]{0,360}dsu-past/.test(src))
  check('E3 十六进制瀑布由 hash+model+bundle 派生', /var seed = String\(F\.hash \|\| 'DSHBOOT'\) \+ '\|' \+ String\(F\.model \|\| ''\)/.test(src))
  check('E4 信号轨迹相位由 hash 派生', /function trace\(\)[\s\S]{0,900}var seed = String\(F\.hash \|\| 'DSHBOOT'\)[\s\S]{0,200}2166136261/.test(src))
  check('E5 清单位于屏幕右侧', /\.dsu-checks \{\s*position: absolute;\s*right: 46px/.test(cssCode))

  /* ── 版式：清单下移后与十六进制瀑布留净空（按 1020 高设计基准） ── */
  const hexBottom = Math.round(1020 * 0.22) + 148
  const checksTops = [...cssCode.matchAll(/\.dsu-checks \{[\s\S]{0,260}?top: (\d+)px/g)].map((m) => Number(m[1]))
  const checksTop = checksTops[checksTops.length - 1]
  check('L1 清单顶边低于瀑布底边（402 > ' + hexBottom + '）', checksTop > hexBottom, 'checksTop=' + checksTop)
  check('L2 窄窗口（<1180px）隐藏清单，避免压主体', /@media \(max-width: 1180px\) \{ \.dsu-checks \{ display: none; \} \}/.test(cssCode))

  /* ── 底部信号轨迹 ── */
  check('T1 轨迹容器 + 5 条基线刻度 + 扫描游标', /\.dsu-trace \{/.test(cssCode) && /\.dsu-trace-base \{/.test(cssCode) && /\.dsu-trace-tick \{/.test(cssCode) && /\.dsu-trace-cursor \{/.test(cssCode))
  check('T2 游标 4.6s 循环扫描', /animation: dsu-trace-scan 4\.6s linear infinite/.test(cssCode))
  check('T3 波形用强调青色而非白色（暗/浅都读得出）', /\.dsu-trace-line \{[\s\S]{0,160}stroke: var\(--dsu-accent-2\)/.test(cssCode))
  check('T4 轨迹随读取阶段出现、终幕撤掉', /ui\.trace\.classList\.add\('dsu-in'\)/.test(src) && /ui\.trace\.classList\.remove\('dsu-in'\)/.test(src))

  /* ── 终幕：浅色不再被光晕洗没 ── */
  check('W1 暗色光晕中心压到 0.55（原 0.99）', /\.dsu-dark \.dsu-bloom \{[\s\S]{0,200}rgba\(255, 250, 240, 0\.55\)/.test(cssCode))
  check('W2 浅色 WELCOME 用白描边短影，不用重黑影', /not\(\.dsu-dark\) \.dsu-w1 \{[\s\S]{0,160}rgba\(255, 255, 255, 0\.55\)/.test(cssCode))
}

console.log('\n[15] 1.6.0 活体光场与文字清晰度')
{
  const src = fs.readFileSync(BUNDLE, 'utf8')
  const css = fs.readFileSync(CSS, 'utf8')
  const cssCode = css.replace(/\/\*[\s\S]*?\*\//g, '')

  check('markup 挂载 Canvas 光场', /<canvas class="dsu-field" aria-hidden="true"><\/canvas>/.test(src))
  check('光场位于底板与档案面板之间', /\.dsu-field \{[\s\S]{0,220}z-index: 11/.test(cssCode) && /\.dsu-watermark \{ z-index: 12; \}/.test(cssCode))
  check('暗色 screen / 浅色 multiply 分开混合', /mix-blend-mode: screen/.test(cssCode) && /not\(\.dsu-dark\) \.dsu-field \{ mix-blend-mode: multiply/.test(cssCode))
  check('Canvas 渲染设备像素比上限 1.75', /Math\.min\(1\.75, Math\.max\(1, Number\(window\.devicePixelRatio\)/.test(src))
  check('无 getContext 的环境直接降级', /typeof cv\.getContext !== 'function'\) return/.test(src))
  check('减少动态时只画静态帧', /matchMedia\('\(prefers-reduced-motion: reduce\)'\)/.test(src) && /if \(!reduced\) raf = window\.requestAnimationFrame\(frame\)/.test(src))
  check('光带读取头沿贝塞尔曲线移动', /var u = \(\(now \* 0\.000034/.test(src))
  check('星尘在中心区域自动降亮', /centerFade = Math\.min\(1, Math\.max\(0\.18/.test(src))
  check('底部水线随时间推进', /0\.745 \+ w \* 0\.052[\s\S]{0,180}now \* 0\.00022/.test(src))
  check('底部轨迹波形 90ms 持续更新', /setInterval\(function \(\) \{ path\.setAttribute\('d', tracePathAt\(Date\.now\(\)\)\) \}, 90\)/.test(src))
  check('结束/重播会停掉光场与轨迹计时器', /stopField\(\)/.test(src) && /clearInterval\(ui\.traceTimer\)/.test(src))
  check('颗粒用 steps 做胶片抖动', /animation: dsu-grain-jitter 760ms steps\(3, end\) infinite/.test(cssCode))
  check('中文用真实 500 字重且禁伪粗', /\.dsu-status \{\s*font-family: var\(--dsu-zh\);\s*font-size: var\(--dsu-title-size\);\s*font-weight: 500;\s*font-synthesis: none;/.test(cssCode))
  check('分隔圆点单独强调', /ch === '·' \? 'dsu-ch dsu-sep'/.test(src) && /\.dsu-status \.dsu-sep \{/.test(cssCode))
  check('自检面板 292px / top 392px', /\.dsu-checks \{[\s\S]{0,80}top: 392px[\s\S]{0,80}width: 292px/.test(cssCode))
  check('自检面板只切右上角，不裁左侧文字', /clip-path: polygon\(0 0, calc\(100% - 14px\) 0, 100% 14px, 100% 100%, 0 100%\)/.test(cssCode))
}

console.log('\n============================')
console.log(`  通过 ${pass} / 失败 ${fail}`)
console.log('============================\n')
process.exit(fail === 0 ? 0 : 1)
