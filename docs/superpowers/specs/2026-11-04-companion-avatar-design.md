# 陪读形象：书旁的 2D 角色与气泡 — 设计文档（切片 1）

- 日期：2026-11-04
- 状态：待用户评审
- 项目目录：`D:\。git`
- 分支：`feature/companion-avatar`（从 `main` 当前 HEAD 切出）

## 1. 意图与背景

陪读现在是一个底部弹出的聊天面板（`CompanionPanel`，`showModalBottomSheet`）。用户希望读的时候**书旁边有一个 2D 形象，冒气泡和读者对话**，而不是每次拉开一个表格。

本期只做第一阶段：**形象出现的位置 + 气泡冒出来**。对话内容、AI 调用、朗读、主动搭话都是后续切片。

已确认的选择：

- 方案 **A（叠加式）**：角色叠在阅读页上，不改正文宽度、不触发重新分页。
- 先开分支做，先落"位置 + 气泡动画"。

## 2. 目标（本期）

1. 打开 TXT/EPUB 阅读页，右下角出现一个角色；它有明确的视觉位置，窗口缩放时跟着走。
2. 角色头顶的气泡**从角色处弹出**（缩放 + 淡入，带回弹），再点一次收回；不遮挡正文主体。
3. 点角色、点气泡都不会翻页（阅读页左右 30% 是翻页热区）。
4. 角色先站在"正文列外侧"；窗口太窄放不下时退到右下角，并缩小一号。
5. 现有 414 个测试保持全绿；新增组件有独立 widget 测试。

## 3. 非目标（本期）

- 不接 `AssistantService`、不接 `TtsService`、不读蒸馏摘要——气泡里只有一条写死的问候语。
- 不做主动说话（翻页/停留/划词触发）、不做对话历史、不做输入框。
- 不做 Live2D、骨骼动画、桌面置顶小窗（方案 C）。
- 不改 `CompanionPanel` 的现有行为（本期它仍然是陪读入口）。

## 4. 反目标（跑起来也算失败）

- **正文被挡**：气泡或角色盖住正文列里的字，或让分页结果变化。
- **抢翻页**：在角色上点一下翻了页，或点在气泡上翻页。
- **布局抖动**：窗口拖动时角色乱跳、气泡跟着文本重排。
- **假动画**：气泡直接出现/消失，没有"冒出来"的过程。

## 5. 约束

- Flutter 3.47 / Dart 3.13，Riverpod 3；无新依赖（不加 rive/lottie）。
- 项目目前**没有任何图片资源**（`pubspec.yaml` 无 assets），所以形象先用代码绘制占位，组件对外暴露 `assetPath`，以后换图不动结构。
- 平台：Windows + Android；窄屏（手机宽度）必须可用。
- 正文列：`reader_page.dart:1012` 起 `Center(SizedBox(width: min(720, maxWidth)))`，内边距 `(20, 16, 20, 32)`。
- 翻页热区：左右各 30% 宽（`reader-prev-zone` / `reader-next-zone`）。

## 6. 方案（已选 A，方案对比见评审记录）

| 方案 | 做法 | 取舍 |
| --- | --- | --- |
| A 叠加（选它） | 阅读页 Stack 上层加角色 + 气泡 | 不动正文宽度、不改分页、测试风险最低；角色会压在页面留白或边距上 |
| B 并排侧栏 | 正文右侧留 160~200px 角色栏 | 最贴"书旁边"，但改 `textWidth` 会重新分页，且要改分页相关断言 |
| C 桌面宠物 | 独立无边框置顶窗口 | 视觉最强，但要动 Windows 原生层，Android 无法对齐，周期以周计 |

## 7. 设计

### 7.1 位置

- 在 `_decorateBody` 的 Stack 里、`contentBody` **之上**（`reader_page.dart:1153` 那个 Stack 再加一层），这样天然盖在翻页热区上面，点角色不会翻页。
- 锚定**右边缘**（用户指定）：`right: 12` 固定，不随正文列居中漂移；垂直方向脚踩在正文底边上方（`bottom: 24`），不做垂直居中。
- 定位规则（`LayoutBuilder`）：
  - 正文列右侧剩余空间 `free = (maxWidth - columnWidth) / 2`；`free >= 168` 时角色整体落在右侧留白里，与正文完全不重叠；
  - 否则贴右边缘（`right: 12, bottom: 12`），尺寸降到小号（高度 120），半透明过渡区只在最右侧一条，尽量减少压字。
- 高度：`clamp(bodyHeight * 0.28, 120, 200)`；宽度按 3:4 比例。
- 用 `AnimatedPositioned`/`Align` 过渡，避免拖动窗口时跳变。

### 7.2 气泡

- 锚点：角色头顶中心，气泡**向左侧展开**（`right` 对齐角色中轴），避免贴右边缘时被裁掉；宽度 `clamp(160, 260)`，最多 4 行，超出省略。
- 动画：`scale 0.6 → 1.0`（`Curves.easeOutBack`）+ `opacity 0 → 1`，180ms；收回反向 120ms。
- 出现时机：进入阅读页 600ms 后自动冒一条问候语；6 秒后自动收起；点角色切换开合。
- 气泡是 `Material` 卡片 + 小三角指向角色；文字可选中关闭（点气泡即收起）。

### 7.3 形象占位

- `CompanionAvatar({assetPath, height})`：有 `assetPath` 走 `Image.asset`；没有则 `CustomPainter` 画一个简化角色（圆头、两只眼、身体、随呼吸轻微上下 1.5px 的 `AnimationController`）。
- 以后给图：PNG 透明底，`pubspec.yaml` 加 assets 即可，不改布局。

### 7.4 状态与开关

- 本期状态只在本页：`_avatarVisible`（默认 true）、`_bubbleOpen`。
- 暂不加设置项；后续切片再接"关闭形象"。

## 8. 测试

- `test/features/companion_avatar_test.dart`：
  - 默认渲染（占位形象存在，气泡初始不在），600ms 后气泡出现，6s 后收起；
  - 点角色开/合；
  - 窄窗口（360×640）下角色贴右边缘、不超出屏幕，气泡不越界；
  - 宽窗口（1400×900）下角色整体落在正文列右侧留白内（左边缘 ≥ 正文列右边缘）。
- `test/features/reader_page_test.dart` 增补：点角色不翻页（页脚页码不变）。
- `flutter analyze` 无问题；`flutter test` 全绿。

## 9. 留给实现者的

- 占位形象的具体画法（只要不丑到出戏）。
- 动画曲线与时长微调。
- 气泡文案（先写一句"读到哪儿了？"）。

## Slice 2 - sprite, grounded line, doorway to the chat
- The avatar wears the bundled Q-version sprite (assets/companion/chibi.png, 314x313 transparent, cut from the user's 474x474 card). companionSprite lives in companion_avatar.dart so the call site never names a path.
- The bubble line comes from companionGreeterProvider: one assistant call per chapter, prompt built from book title, chapter title and the first 400 chars of the current page, answer condensed to a single sentence (<=48 chars, quotes stripped). Unconfigured or failing calls return null and the bubble falls back to '读到哪儿了？'.
- CompanionPresence waits at most 3s for that line, then pops with whatever it has.
- Tapping the character or the bubble hands control to onOpenChat (the existing CompanionPanel); without a handler the old toggle behaviour stays, which is what the widget tests exercise.

## Slice 3 - the character actually moves now

- 用户给的是 Cubism 2.1 模型（`加藤惠live2d.zip`，`.moc` + 2048 贴图 + 16 个 mtn），只有 Web 运行时能加载，而 Windows 上跑 WebView 要加原生插件——本机没开开发者模式，构建直接卡在 symlink 上。所以没有做实时运行，改成**离线烘焙**：用真 Live2D 运行时（pixi-live2d-display cubism2 + live2d.min.js）在 Edge headless 里把 `katou_01` 的 idle 动作逐帧渲染成 PNG，导成一张 spritesheet 交给 Flutter 播放。
- 烘焙参数（脚本都在 `.superpowers/spikes/live2d/`，可重跑）：80 帧 @20fps，挑出首尾最接近的一段做循环，最终锁 **frames 8..69（62 帧）**、接缝差分 0.0645；并集 alpha bbox `(256,387,508,960)` 缩放成 **169x384/格**，8 列 × 8 行 → `assets/companion/chibi_idle.png`（1352x3072，约 1.1MB）。
- 播放器 `CompanionIdleSprite({animate = true})`：`Ticker` 按 `fps` 取模选帧，`rootBundle.load` + `instantiateImageCodec` 解码整张，`drawImageRect` 做 contain + 底部居中；`companionIdleFrameCount/Columns/FrameSize/Fps` 四个常量跟 spritesheet 一起改。
- `CompanionAvatar` 的换装点还是 `assetPath`：等于 `companionSprite` 时走 idle 播放器，其它路径仍是静态图，占位画师逻辑不变。
- 测试里必须静止：`FLUTTER_TEST=true` 时 `animate: false`（`Platform.environment` 判断），否则阅读页那批 `pumpAndSettle()` 永远等不到 settle。
- 构建环境的坑：加了插件依赖后 `flutter build windows` 要求 symlink 权限（本机非管理员、开发者模式未开）。绕法是先 `mklink /J` 把 `windows/flutter/ephemeral/.plugin_symlinks/*` 建成 junction，Flutter 认路径一致就直接复用，构建通过。

## Slice 4 - a pet that answers the reader's hands

- 形象换成 dsh-pet 风格的桌面宠物（用户要求）：素材来自 `C:\Users\q\.dsh\profiles\desktop\node_modules\dsh-pet\assets\webm`（MIT），VP9 + 独立 alpha，必须用 `ffmpeg -c:v libvpx-vp9 -pix_fmt rgba` 抽帧才有透明通道。
- 烘焙脚本 `.superpowers/spikes/pet/bake_clips.py`：按 alpha>128 的阈值取 bbox（直接 `Image.getbbox()` 会把整幅 640x360 都算进来），每格 150x200、8 列、12fps；idle 用 72 帧窗口做首尾接缝最小化，poke / drag 取完整片段。产物 `assets/companion/pet_idle.png`（36 帧）、`pet_poke.png`、`pet_drag.png`（48 帧）。
- 播放器 `CompanionClip` + `CompanionClipStage`：Ticker 自己的 `elapsed` 就是从 start 起算的时间，不要再建 epoch；一次性片段播完自动回 idle。
- 身体 `CompanionBody`：位置/压扁/倾斜三组弹簧（k=90/300/120，c=11/18/10），`Listener.onPointerDown` 按下即压扁（不能等 onTapDown，竞技场会延迟 ~100ms），拖拽上限 48x28 px，松手带回惯性并落地压扁，hover 时倾斜并把归一化指针位置写进 `look`。
- `CompanionAvatar` 把动作接到身体上：按下播 poke、拖动播 drag、松手回 idle；`idleMotion: false` 或 `FLUTTER_TEST=true` 时静止，保证 `pumpAndSettle()` 能结束。

## Slice 5 - two more reactions

- 翻页惊一下：`CompanionPresence` 收一个 `ValueListenable<int>? pageTurns`，阅读页在 `_goToNextPage` / `_goToPreviousPage` 里 `_pageTurns.value++`，presence 监听后播 `companionSurpriseClip`（`pet_surprise.png`，48 帧）。
- 说话挥手：气泡打开时先 `cheer()`（身体弹一下）再播 `companionWaveClip`（`pet_wave.png`，24 帧；源片段从第 2 秒起才是挥手，所以烘焙时 `skip=24`）。
- 两个片段都不阻塞交互：一次性播放完自动回 idle，气泡的 6 秒逗留计时不受影响。
