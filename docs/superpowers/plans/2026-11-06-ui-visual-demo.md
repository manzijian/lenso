# LENSO UI 视觉 Demo 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 产出一个单文件 HTML 视觉 Demo（`demo/lenso-ui-demo.html`），展示 LENSO 主图库核心界面效果，用于在原生开发前确认设计方向。

**Architecture:** 纯 HTML + 内联 CSS + 少量原生 JS（tab 切换），无构建、无依赖。页面模拟 macOS 窗口框架，内容为 SwiftUI 将实现的四个视图的静态呈现。

**Tech Stack:** HTML5 / CSS3（系统字体栈 `-apple-system`）/ 原生 JavaScript

**约束（源自 LENSO 架构规范第十五章）：**
- 精致、克制的 Apple 原生视觉语言，图片是视觉主体
- 避免厚重标题栏、过多边框、无意义卡片、复杂工具面板、过度渐变、过度动画、企业后台布局
- Liquid Glass 方向（subtle backdrop blur，不是处处玻璃）
- 界面语言：简体中文（同时体现设计系统一致性）

---

### Task 1: 项目初始化与 Demo 骨架

**Files:**
- Create: `demo/lenso-ui-demo.html`
- Create: `.gitignore`

- [ ] **Step 1: 初始化 Git 仓库（若未初始化）**

```bash
cd /Users/zijian/projects/lenso && git init && git add -A && git commit -m "chore: init repository"
```

Expected: 空仓库初始化成功，首次提交完成。

- [ ] **Step 2: 创建 .gitignore**

```gitignore
.DS_Store
build/
DerivedData/
*.xcodeproj/project.xcworkspace/xcuserdata/
xcuserdata/
.swiftpm/
```

- [ ] **Step 3: 创建 HTML 骨架（仅结构，无样式内容）**

创建 `demo/lenso-ui-demo.html`，包含：

```html
<!DOCTYPE html>
<html lang="zh-Hans">
<head>
<meta charset="UTF-8">
<title>LENSO — UI 视觉 Demo</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>/* Task 2-4 填充 */</style>
</head>
<body>
<!-- Task 2-4 填充 -->
<script>/* Task 5 填充 */</script>
</body>
</html>
```

- [ ] **Step 4: Commit**

```bash
git add demo/ .gitignore && git commit -m "chore: add UI demo skeleton"
```

---

### Task 2: 设计 Token 与页面框架（macOS 窗口 chrome + 顶栏 Tab）

**Files:**
- Modify: `demo/lenso-ui-demo.html`（填充 `<style>` 的基础部分与 `<body>` 框架）

- [ ] **Step 1: 写失败的视觉检查点**

本任务是纯视觉工作，无自动化测试。验证方式：在浏览器打开文件，人工核对下述 Step 3 的每个视觉断言（这就是"看测试失败→通过"的人工等价物；开发正式 SwiftUI 时，对应 DesignSystem token 会有单元测试）。

- [ ] **Step 2: 定义 CSS Token（对应规范 15.2 DesignSystem）**

```css
:root {
  /* Color Tokens — 浅色为默认，深色见 prefers-color-scheme */
  --bg-canvas: #f5f5f7;
  --bg-surface: #ffffff;
  --bg-material: rgba(255, 255, 255, 0.72);   /* Liquid Glass 材质 */
  --bg-material-dark: rgba(40, 40, 44, 0.6);
  --text-primary: #1d1d1f;
  --text-secondary: #6e6e73;
  --text-tertiary: #aeaeb2;
  --accent: #0a84ff;                            /* Apple 系统蓝 */
  --accent-soft: rgba(10, 132, 255, 0.12);
  --border-hairline: rgba(0, 0, 0, 0.08);
  --danger: #ff3b30;

  /* Typography */
  --font-ui: -apple-system, BlinkMacSystemFont, "SF Pro Text", "PingFang SC", "Helvetica Neue", sans-serif;
  --fs-large-title: 28px;
  --fs-title: 20px;
  --fs-body: 14px;
  --fs-caption: 12px;

  /* Spacing & Radius */
  --sp-1: 4px;  --sp-2: 8px;  --sp-3: 12px;
  --sp-4: 16px; --sp-5: 24px; --sp-6: 32px;
  --radius-window: 12px;
  --radius-card: 8px;
  --radius-thumb: 6px;

  /* Elevation */
  --shadow-window: 0 24px 80px rgba(0,0,0,0.28), 0 4px 16px rgba(0,0,0,0.12);
  --shadow-popover: 0 12px 32px rgba(0,0,0,0.16);
}
@media (prefers-color-scheme: dark) { :root { …深色映射… } }
```

- [ ] **Step 3: 页面框架 — 模拟 macOS 窗口**

```html
<body>
  <div class="stage">                 <!-- 灰色画布背景，居中承载窗口 -->
    <div class="mac-window">          <!-- 12px 圆角 + --shadow-window -->
      <header class="titlebar">       <!-- 52px 高，--bg-material + backdrop-filter: blur(20px) -->
        <div class="traffic-lights">  <!-- 红/黄/绿三个 12px 圆点 -->
          <span class="tl tl-close"></span>
          <span class="tl tl-min"></span>
          <span class="tl tl-zoom"></span>
        </div>
        <div class="window-title">图库</div>
        <div class="titlebar-actions">
          <button class="tb-btn" title="全局搜索">⌕</button>
          <button class="tb-btn" title="设置">⚙</button>
        </div>
      </header>
      <nav class="view-tabs">         <!-- 图库 / 搜索 / OCR / 设置 四个 tab -->
        <button class="tab active" data-view="library">图库</button>
        <button class="tab" data-view="search">搜索</button>
        <button class="tab" data-view="ocr">OCR 工作区</button>
        <button class="tab" data-view="settings">设置</button>
      </nav>
      <main class="view-container">
        <section id="view-library" class="view active">…Task 3…</section>
        <section id="view-search" class="view">…Task 4…</section>
        <section id="view-ocr" class="view">…Task 4…</section>
        <section id="view-settings" class="view">…Task 4…</section>
      </main>
      <footer class="statusbar">      <!-- 32px 高，caption 字号，secondary 色 -->
        共 128 张截图 · 上次备份：未启用云备份
      </footer>
    </div>
    <p class="demo-note">LENSO UI 视觉 Demo — 静态演示，代表未来 SwiftUI 界面的视觉方向</p>
  </div>
</body>
```

- [ ] **Step 4: 浏览器人工验证清单**

打开 `demo/lenso-ui-demo.html` 核对：
1. 窗口有 12px 圆角和大阴影，浮在灰画布上
2. 红黄绿交通灯在左上
3. 顶栏毛玻璃模糊效果可见（窗口下方垫深色演示图片以体现 blur）
4. 四个 tab 正常渲染（此时切换无内容是预期的——"测试失败"状态）

- [ ] **Step 5: Commit**

```bash
git add demo/lenso-ui-demo.html && git commit -m "feat(demo): window chrome and design tokens"
```

---

### Task 3: 图库视图（核心视图）

**Files:**
- Modify: `demo/lenso-ui-demo.html`（填充 `#view-library`）

- [ ] **Step 1: 写失败的视觉检查点**

浏览器打开，`#view-library` 当前为空 → 断言"图库应显示侧栏+网格"失败。这就是 RED。

- [ ] **Step 2: 实现 HTML 结构**

```html
<section id="view-library" class="view active">
  <aside class="sidebar">
    <div class="side-group">
      <div class="side-title">图库</div>
      <a class="side-item active">全部截图 <span class="count">128</span></a>
      <a class="side-item">临时截图 <span class="count">6</span></a>
      <a class="side-item">已置顶 <span class="count">3</span></a>
    </div>
    <div class="side-group">
      <div class="side-title">相册</div>
      <a class="side-item">工作资料 <span class="count">42</span></a>
      <a class="side-item">代码片段 <span class="count">31</span></a>
      <a class="side-item">发票收据 <span class="count">18</span></a>
      <button class="side-add">＋ 新建相册</button>
    </div>
    <div class="side-group">
      <div class="side-title">标签</div>
      <div class="tag-cloud">
        <span class="tag-chip">接口文档</span>
        <span class="tag-chip">会议记录</span>
        <span class="tag-chip">UI 灵感</span>
        <span class="tag-chip">报错日志</span>
      </div>
    </div>
  </aside>
  <div class="library-main">
    <div class="library-toolbar">
      <div class="seg-control">          <!-- 时间分组切换 -->
        <button class="seg active">天</button>
        <button class="seg">月</button>
        <button class="seg">年</button>
      </div>
      <div class="toolbar-filter">
        <span class="filter-chip">来源：全部 ▾</span>
        <span class="filter-chip">标签：全部 ▾</span>
      </div>
    </div>
    <div class="library-scroll">
      <div class="date-section">
        <h3 class="date-header">今天 · 11 月 6 日</h3>
        <div class="thumb-grid">
          <!-- 每个缩略图：图片 + 悬浮信息 + 应用角标 -->
          <figure class="thumb" tabindex="0">
            <img src="…" alt="Safari 网页截图">
            <span class="app-badge">S</span>
            <figcaption class="thumb-meta">14:32 · Safari</figcaption>
          </figure>
          <!-- × 12 左右，用真实感的占位图（CSS 渐变模拟界面截图） -->
        </div>
      </div>
      <div class="date-section">…昨天…</div>
      <div class="date-section">…本周早些时候…</div>
    </div>
  </div>
</section>
```

- [ ] **Step 3: 关键样式规则**

```css
/* 布局 */
#view-library { display: grid; grid-template-columns: 200px 1fr; }
.sidebar { border-right: 1px solid var(--border-hairline); padding: var(--sp-4); }
.side-item.active { background: var(--accent-soft); color: var(--accent); border-radius: var(--radius-card); }

/* 缩略图网格 — 图片是视觉主体：无卡片边框、无阴影、直接圆角图 */
.thumb-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(160px, 1fr)); gap: var(--sp-3); }
.thumb { border-radius: var(--radius-thumb); overflow: hidden; position: relative; }
.thumb img { display: block; width: 100%; aspect-ratio: 16/10; object-fit: cover; }
.thumb:hover { outline: 2px solid var(--accent); outline-offset: -2px; }  /* hover 仅描边 */
.app-badge { position: absolute; top: 6px; left: 6px; width: 18px; height: 18px;
  border-radius: 5px; background: var(--bg-material); backdrop-filter: blur(8px);
  font-size: 10px; display: grid; place-items: center; }
.thumb-meta { position: absolute; bottom: 0; left: 0; right: 0;
  padding: 14px 8px 6px; font-size: var(--fs-caption); color: #fff;
  background: linear-gradient(transparent, rgba(0,0,0,0.45)); }
```

- [ ] **Step 4: 占位截图生成方式**

用 CSS 渐变模拟不同界面截图（代码编辑器深色、Safari 白色网页、微信聊天、PDF 文档、会议幻灯片），每个 `<img>` 用内联 SVG data-URI 或纯 `div.thumb-ph` + 渐变类实现，例如：

```css
.ph-editor  { background: linear-gradient(135deg, #1e1e2e 0%, #2a2a3d 100%); }
.ph-web     { background: linear-gradient(180deg, #fff 0 30%, #f0f0f2 30% 100%); }
.ph-chat    { background: linear-gradient(180deg, #ededed 0%, #e0e0e0 100%); }
.ph-doc     { background: #fafafa; }
.ph-slides  { background: linear-gradient(135deg, #0a84ff22, #0a84ff11), #fff; }
```

- [ ] **Step 5: 浏览器人工验证清单**

1. 侧栏分组（图库/相册/标签）清晰，计数右对齐
2. 缩略图无边框卡片感，hover 出现蓝色描边
3. 时间分组标题"今天 · 11 月 6 日"显示
4. 应用角标毛玻璃效果

- [ ] **Step 6: Commit**

```bash
git add demo/lenso-ui-demo.html && git commit -m "feat(demo): library view with sidebar and thumbnail grid"
```

---

### Task 4: 搜索 / OCR / 设置三个次级视图

**Files:**
- Modify: `demo/lenso-ui-demo.html`（填充 `#view-search` / `#view-ocr` / `#view-settings`）

- [ ] **Step 1: 写失败的视觉检查点**

浏览器打开，三个 tab 切换后内容为空 → RED。

- [ ] **Step 2: 搜索视图**

```html
<section id="view-search" class="view">
  <div class="search-wrap">
    <div class="search-bar">⌕ <input placeholder="搜索截图内容、应用、标签…">
      <span class="search-scope">全文 · 结构化</span>
    </div>
    <div class="search-filters">
      <span class="filter-chip active">全部</span>
      <span class="filter-chip">来源应用</span>
      <span class="filter-chip">OCR 文字</span>
      <span class="filter-chip">标签</span>
      <span class="filter-chip">时间</span>
    </div>
    <div class="search-results">
      <div class="result-row">    <!-- 横向结果行：小图 + 元信息 + OCR 摘录 -->
        <div class="result-thumb ph-editor"></div>
        <div class="result-info">
          <div class="result-title">Xcode — CaptureService.swift</div>
          <div class="result-snippet">… FT S5 分词器需要针对<mark>中文</mark>验证召回率 …</div>
          <div class="result-meta">11 月 5 日 16:20 · Xcode · 标签：报错日志</div>
        </div>
      </div>
      <!-- × 5 结果行，其中 OCR 命中词用 <mark> -->
    </div>
  </div>
</section>
```

样式要点：结果行之间用 hairline 分隔而非卡片；`mark` 用 `--accent-soft` 背景。

- [ ] **Step 3: OCR 工作区视图**

```html
<section id="view-ocr" class="view">
  <div class="ocr-split">
    <div class="ocr-image-pane">
      <div class="ocr-image ph-doc">   <!-- 模拟一张文档截图 -->
        <div class="ocr-box" style="top:12%;left:8%;width:60%;height:6%"></div>
        <!-- 若干文字定位框，hover 高亮，对应右侧文字块 -->
      </div>
    </div>
    <div class="ocr-text-pane">
      <div class="ocr-toolbar">
        <button class="btn-primary">重新识别</button>
        <button class="btn-secondary">复制全文</button>
        <span class="ocr-lang">简体中文 · 置信度 96%</span>
      </div>
      <div class="ocr-blocks">
        <p class="ocr-block" data-box="0">项目技术目标：LENSO 是一款 macOS 原生智能截图工具…</p>
        <!-- 每块 hover 联动左侧定位框高亮 -->
      </div>
      <div class="ocr-translate">
        <div class="ocr-translate-head">翻译 <span class="ocr-lang">英 → 中</span></div>
        <p class="translation-text">Project goals: LENSO is a native macOS smart screenshot tool…</p>
      </div>
    </div>
  </div>
</section>
```

样式要点：左右分栏 55/45，中间 hairline 分隔；`.ocr-box` 用 `--accent` 半透明描边框表示识别区域，hover 时填充 `--accent-soft`。

- [ ] **Step 4: 设置视图**

```html
<section id="view-settings" class="view">
  <div class="settings-wrap">
    <h2 class="settings-title">设置</h2>
    <div class="settings-group">
      <div class="settings-group-title">截图</div>
      <label class="setting-row">
        <span>截图后自动复制到剪贴板</span>
        <span class="switch on"></span>
      </label>
      <label class="setting-row">
        <span>默认保存格式</span>
        <span class="setting-value">PNG ▾</span>
      </label>
    </div>
    <div class="settings-group">
      <div class="settings-group-title">智能分类</div>
      <label class="setting-row">
        <span>自动标签（基于来源应用）</span>
        <span class="switch on"></span>
      </label>
      <label class="setting-row">
        <span>自动标签（基于 OCR 内容）</span>
        <span class="switch off"></span>
      </label>
    </div>
    <div class="settings-group">
      <div class="settings-group-title">权限</div>
      <div class="setting-row permission-row">
        <span>屏幕录制</span>
        <span class="perm-status ok">已授权</span>
      </div>
      <div class="setting-row permission-row">
        <span>通知</span>
        <button class="btn-secondary">去开启</button>
      </div>
    </div>
    <div class="settings-group">
      <div class="settings-group-title">关于</div>
      <label class="setting-row"><span>检查更新</span><span class="setting-value">V1.0</span></label>
    </div>
  </div>
</section>
```

样式要点：分组用半透明分组底 + hairline 行分隔（iOS 风格 inset grouped list），开关用纯 CSS 实现的绿色 toggle。

- [ ] **Step 5: 浏览器人工验证清单**

1. 三个 tab 切换正常，互不干扰
2. 搜索结果 OCR 命中词 `<mark>` 高亮
3. OCR 分栏布局正常，定位框可 hover
4. 设置开关视觉状态正确（on 绿 / off 灰）

- [ ] **Step 6: Commit**

```bash
git add demo/lenso-ui-demo.html && git commit -m "feat(demo): search, OCR workspace and settings views"
```

---

### Task 5: Tab 切换交互 + 整体验收

**Files:**
- Modify: `demo/lenso-ui-demo.html`（填充 `<script>`）

- [ ] **Step 1: 实现 Tab 切换 JS（事件委托，约 10 行）**

```javascript
document.querySelector('.view-tabs').addEventListener('click', (e) => {
  const tab = e.target.closest('.tab');
  if (!tab) return;
  document.querySelectorAll('.tab').forEach(t => t.classList.toggle('active', t === tab));
  document.querySelectorAll('.view').forEach(v =>
    v.classList.toggle('active', v.id === `view-${tab.dataset.view}`));
});
```

- [ ] **Step 2: 浏览器全量验收**

逐项核对四个视图的 Task 验证清单 + 以下整体项：
1. `prefers-color-scheme: dark` 下整体协调（用系统设置切换验证）
2. 页面在 1280px 和 900px 宽度下布局不破
3. 无横向滚动条
4. 控制台无 JS 错误

- [ ] **Step 3: Commit**

```bash
git add demo/lenso-ui-demo.html && git commit -m "feat(demo): tab switching and final polish"
```

- [ ] **Step 4: 提示用户打开查看**

```bash
open /Users/zijian/projects/lenso/demo/lenso-ui-demo.html
```

---

## Self-Review 结果

1. **Spec coverage:** 规范要求的四个核心界面（图库/搜索/OCR/设置）均有对应任务 ✓；设计 token 对应 15.2 ✓；克制原生视觉原则体现在具体 CSS 规则（无边框卡片、hairline、单一 accent）✓
2. **Placeholder scan:** 无 TBD/TODO；Task 3/4 的重复结构已给出完整示例代码和重复说明（×N 表示语义而非省略）✓
3. **Type consistency:** HTML id 命名（`view-library` 等）与 JS `data-view` 值一一对应 ✓；CSS token 命名在 Task 2 定义、Task 3/4 引用一致 ✓
