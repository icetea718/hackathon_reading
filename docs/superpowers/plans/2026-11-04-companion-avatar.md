# 陪读形象（切片 1：位置 + 气泡弹出）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development (recommended) or executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 阅读页右下角常驻一个 2D 角色，头顶气泡以弹出动画冒出/收回，点角色可开合，点它不翻页。

**Architecture:** 新增 `CompanionAvatar`（纯展示形象，占位用 `CustomPainter`，留 `assetPath` 口子）和 `CompanionPresence`（形象 + 气泡 + 定时器/动画状态机）。在 `reader_page.dart` 的 `_decorateBody` 里把 `CompanionPresence` 叠加到正文之上、按右边缘定位。

**Tech Stack:** Flutter 3.47 / Dart 3.13，无新增依赖；`flutter_test` widget 测试。

**Spec:** `docs/superpowers/specs/2026-11-04-companion-avatar-design.md`

## Global Constraints

- 不引入新依赖（不加 rive/lottie/任何动画包）。
- 不改变正文宽度与分页结果（`textWidth`、`reader_page.dart:1012` 的 720 上限不动）。
- 现有 414 个测试必须保持全绿；`flutter analyze` 无问题。
- 平台：Windows + Android，窄屏可用。
- **不能有无限循环动画**：阅读页测试大量使用 `pumpAndSettle()`，重复 `AnimationController` 会让它永不 settle。呼吸/眨眼这类常驻动画本期不做。
- 定时器必须在 `dispose()` 里取消，否则 widget 测试报 "A Timer is still pending"。
- 气泡文案本期写死：`读到哪儿了？`。

## Review Focus

- 窗口从宽拖到窄：角色在"右侧留白"和"贴右边缘小号"之间切换时不能跳出屏幕、不能盖住页脚。
- 点击角色/气泡绝不能翻页（左右 30% 是翻页热区）。
- 多次快速点击角色：动画与 6 秒自动收起定时器不能打架（不出现"收了又自己弹"）。
- 漫画模式（`_decorateBody(companionEnabled: false)`）不应出现形象。
- 窄屏（360 宽）下气泡向左展开不能被裁切。

---

### Task 1: 形象组件 `CompanionAvatar`

**Files:**
- Create: `lib/features/companion/companion_avatar.dart`
- Test: `test/features/companion_avatar_test.dart`

**Interfaces:**
- Produces:
  - `class CompanionAvatar extends StatefulWidget { const CompanionAvatar({super.key, this.assetPath, required this.height}); final String? assetPath; final double height; }`
  - 内部 `Key('companion-avatar')` 落在实际绘制盒子上；无 `assetPath` 时用 `CustomPainter` 画占位角色。
  - 尺寸：`height` 给定，宽度 = `height * 0.75`（3:4）。
  - 入场：一次性 400ms「轻微上浮 + 缩放」，不循环。

- [ ] **Step 1: 写失败测试**

```dart
// test/features/companion_avatar_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon_reading/features/companion/companion_avatar.dart';

void main() {
  testWidgets('draws a 3:4 placeholder when no asset is given', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: CompanionAvatar(height: 160))),
      ),
    );
    await tester.pumpAndSettle();

    final rect = tester.getRect(find.byKey(const Key('companion-avatar')));
    expect(rect.height, 160);
    expect(rect.width, 120);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('honours the height it is given', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: CompanionAvatar(height: 120))),
      ),
    );
    await tester.pumpAndSettle();

    final rect = tester.getRect(find.byKey(const Key('companion-avatar')));
    expect(rect.height, 120);
    expect(rect.width, 90);
  });
}
```

- [ ] **Step 2: 运行确认失败**

Run: `flutter test test/features/companion_avatar_test.dart`
Expected: FAIL — `Target of URI doesn't exist` / `CompanionAvatar isn't defined`.

- [ ] **Step 3: 实现**

`CompanionAvatar` 用 `SingleTickerProviderStateMixin` 跑一次入场动画（`Curves.easeOutBack`，400ms，`scale 0.94→1` + `translateY 6→0`），结束后不循环。无 `assetPath` 时 `CustomPaint` 画占位：圆头、两只眼睛、圆角身体，颜色取 `Theme.of(context).colorScheme.primary`/`surfaceContainerHighest`；有 `assetPath` 时 `Image.asset(assetPath, fit: BoxFit.contain)`。

- [ ] **Step 4: 运行确认通过**

Run: `flutter test test/features/companion_avatar_test.dart`
Expected: PASS (2 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/features/companion/companion_avatar.dart test/features/companion_avatar_test.dart
git commit -m "feat(companion): add 2D avatar sprite with placeholder painter"
```

---

### Task 2: 气泡 `CompanionPresence`

**Files:**
- Create: `lib/features/companion/companion_presence.dart`
- Test: `test/features/companion_presence_test.dart`

**Interfaces:**
- Consumes: `CompanionAvatar`（Task 1）。
- Produces:

```dart
class CompanionPresence extends StatefulWidget {
  const CompanionPresence({
    super.key,
    this.assetPath,
    this.height = 160,
    this.greeting = '读到哪儿了？',
    this.autoGreet = true,
  });
}
```

- 结构：`Column(mainAxisSize: min, crossAxisAlignment: end)`，上气泡下形象；气泡 `Key('companion-bubble')`，带 `Key('companion-bubble-scale')` 的 `ScaleTransition`（`alignment: Alignment.bottomRight`）。
- 行为：挂载后 600ms 自动冒泡（`autoGreet` 为真时）；冒泡动画 180ms `easeOutBack` + 淡入；6 秒后自动收起（120ms 反向）；点形象开合；点气泡收起；任何开合都重置/取消定时器。

- [ ] **Step 1: 写失败测试**

```dart
// test/features/companion_presence_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon_reading/features/companion/companion_presence.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  testWidgets('greets with a popping bubble then hides itself', (tester) async {
    await tester.pumpWidget(_host(const CompanionPresence(height: 160)));
    expect(find.byKey(const Key('companion-bubble')), findsNothing);

    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 90));
    final scale = tester
        .widget<ScaleTransition>(find.byKey(const Key('companion-bubble-scale')))
        .scale
        .value;
    expect(scale, greaterThan(0.0));
    expect(scale, lessThan(1.0));

    await tester.pumpAndSettle();
    expect(find.text('读到哪儿了？'), findsOneWidget);

    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('companion-bubble')), findsNothing);
  });

  testWidgets('tapping the avatar opens and closes the bubble', (tester) async {
    await tester.pumpWidget(
      _host(const CompanionPresence(height: 160, autoGreet: false)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('companion-avatar')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('companion-bubble')), findsOneWidget);

    await tester.tap(find.byKey(const Key('companion-avatar')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('companion-bubble')), findsNothing);
  });

  testWidgets('tapping the bubble closes it', (tester) async {
    await tester.pumpWidget(
      _host(const CompanionPresence(height: 160, autoGreet: false)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('companion-avatar')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('companion-bubble')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('companion-bubble')), findsNothing);
  });
}
```

- [ ] **Step 2: 运行确认失败**

Run: `flutter test test/features/companion_presence_test.dart`
Expected: FAIL — `companion_presence.dart` 不存在。

- [ ] **Step 3: 实现**

一个 `AnimationController(duration: 180ms)` + `CurvedAnimation(easeOutBack)`；`_open`/`_close` 用 `forward`/`reverse`，`reverse` 用 120ms（`reverseDuration`）。气泡存在性由 `_bubbleVisible` 控制，`reverse()` 完成后 `setState` 移出树。自动收起用 `Timer`（`_hideTimer`），在 `dispose`、开合、点击时取消。气泡：`Material` 圆角卡片 + 底部小三角（`CustomPaint` 或 `Transform.rotate` 的方块），`maxWidth: 260`，`maxLines: 4`，`overflow: ellipsis`；外层 `Padding(right: 0)` 以贴右。

- [ ] **Step 4: 运行确认通过**

Run: `flutter test test/features/companion_presence_test.dart`
Expected: PASS (3 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/features/companion/companion_presence.dart test/features/companion_presence_test.dart
git commit -m "feat(companion): pop a speech bubble above the avatar"
```

---

### Task 3: 接进阅读页（右边缘定位 + 不抢翻页）

**Files:**
- Modify: `lib/features/reader/reader_page.dart`（`_decorateBody`，1122-1209；漫画分支调用点 1290 附近）
- Test: `test/features/reader_page_test.dart`（追加）

**Interfaces:**
- Consumes: `CompanionPresence`（Task 2）。
- Produces: 阅读页内 `Key('companion-presence')`；漫画模式无此 key。

- [ ] **Step 1: 写失败测试**（追加到 `test/features/reader_page_test.dart`，复用文件里已有的建库/建书 helper 与 pump 流程）

```dart
testWidgets('avatar hugs the right margin when the window is wide', (tester) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await _pumpReader(tester); // 复用文件内现有 helper 名

  final page = tester.getRect(find.byKey(const Key('reader-page')));
  final avatar = tester.getRect(find.byKey(const Key('companion-avatar')));
  final columnRight = page.center.dx + 360; // 720 宽正文列居中
  expect(avatar.left, greaterThanOrEqualTo(columnRight));
  expect(avatar.right, lessThanOrEqualTo(page.right));
  expect(avatar.bottom, lessThanOrEqualTo(page.bottom));
});

testWidgets('avatar shrinks and stays on screen in a narrow window', (tester) async {
  tester.view.physicalSize = const Size(360, 640);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await _pumpReader(tester);

  final avatar = tester.getRect(find.byKey(const Key('companion-avatar')));
  final page = tester.getRect(find.byKey(const Key('reader-page')));
  expect(avatar.height, 120);
  expect(avatar.right, lessThanOrEqualTo(360));
  expect(avatar.bottom, lessThanOrEqualTo(page.bottom));
});

testWidgets('tapping the avatar does not turn the page', (tester) async {
  await _pumpReader(tester);
  final footer = find.textContaining('第 1 /').evaluate().isEmpty
      ? find.textContaining('/ 1 页')
      : find.textContaining('第 1 /');
  final before = tester.widget<Text>(footer.first).data;

  await tester.tap(find.byKey(const Key('companion-avatar')));
  await tester.pumpAndSettle();

  expect(tester.widget<Text>(find.text(before!)).data, before);
});
```

- [ ] **Step 2: 运行确认失败**

Run: `flutter test test/features/reader_page_test.dart`
Expected: FAIL — 找不到 `companion-avatar`。

- [ ] **Step 3: 实现**

在 `_decorateBody` 里新增：

```dart
Widget _withAvatar(Widget content) {
  return LayoutBuilder(builder: (context, constraints) {
    final columnWidth = constraints.maxWidth < 720 ? constraints.maxWidth : 720.0;
    final free = (constraints.maxWidth - columnWidth) / 2;
    final tall = free >= 168;
    return Stack(
      fit: StackFit.expand,
      children: [
        content,
        Positioned(
          right: 12,
          bottom: tall ? 24 : 12,
          child: CompanionPresence(
            key: const Key('companion-presence'),
            height: tall
                ? (constraints.maxHeight * 0.28).clamp(120.0, 200.0)
                : 120,
          ),
        ),
      ],
    );
  });
}
```

- 两个分支都套：`_railPinned` 时 `Expanded(child: _withAvatar(contentBody))`；否则 Stack 里把 `contentBody` 换成 `_withAvatar(contentBody)`（注意 `_withAvatar` 自身是 Stack，翻页热区在 `contentBody` 内部，形象在其上，天然不被抢点击）。
- 漫画分支 `_decorateBody(contentBody, companionEnabled: false)`：`companionEnabled == false` 时不套 `_withAvatar`。
- 不得改动 `textWidth` 相关逻辑。

- [ ] **Step 4: 运行确认通过（含既有阅读页测试）**

Run: `flutter test test/features/reader_page_test.dart test/features/reader_companion_test.dart test/features/reader_rail_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/features/reader/reader_page.dart test/features/reader_page_test.dart
git commit -m "feat(companion): pin the avatar to the reader's right edge"
```

---

### Task 4: 全量验证与实机效果

**Files:** 无新增

- [ ] **Step 1: 全量测试**

Run: `flutter test`
Expected: 全部通过（≥ 414 + 新增）。

- [ ] **Step 2: 静态检查**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 3: 构建并运行 Windows 版，截图确认效果**

Run: `flutter build windows --debug`，启动 exe，进入任意一本书的阅读页，截图确认：角色贴右边缘、气泡 600ms 后弹出、点角色收回、点角色不翻页。

- [ ] **Step 4: Commit（若有构建产物外的改动）**

```bash
git add -A docs/superpowers/specs docs/superpowers/plans
git commit -m "docs(companion): record avatar slice-1 spec and plan" || true
```
