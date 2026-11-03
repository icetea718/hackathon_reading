# hackathon_reading

一个面向 Windows 和 Android 的本地阅读器（Flutter），为后续的 AI 陪读、AI 翻译、划重点解读预留接口。当前为 **Phase 1：TXT / EPUB / PDF 阅读与书签**。

想一起开发？环境搭建、开发流程、代码约定和扩展指引见 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 已实现（Phase 1）

- 书架：导入、展示、删除书籍，本地保存副本。
- 导入格式：TXT、EPUB、PDF，三种格式都可在应用内打开阅读。
- 重复导入保护：按文件内容计算 SHA-256，导入已在书架中的同一文件时提示「这本书已经在书架中」并跳过；旧版本导入的书在首次导入时自动补算哈希。
- TXT 编码自动识别：UTF-8（含 BOM）、UTF-16 LE/BE（含 BOM）、GB18030/GBK/GB2312；无法严格解码时按 UTF-8 容错处理。
- TXT 章节识别：基于行首标题规则（`第X章/节/卷/回/部/篇/集`、序章、楔子、前言、番外、`Chapter N` 等），无标题时整本书作为一章；误判控制：过长的行或句末带标点的行不会当作标题。
- EPUB 解析：支持 EPUB3 导航目录（nav）和 EPUB2 NCX 目录，按 spine 顺序提取正文纯文本并统一字符偏移；跳过导航页和纯封面页；损坏文件导入失败且不留下脏数据。目前只提取纯文本，不还原 CSS 样式、图片和封面。
- 阅读器：目录抽屉跳章、上一章/下一章、字号 14–28、行距 1.2–2.0、浅色/米色/深色背景（本次会话内生效）；正文按章节懒加载，调整字号或窗口大小后会保持在原阅读位置。
- 书签：阅读页可给当前章节添加/取消书签；抽屉的“书签”栏列出全部书签，支持跳转和删除；跳到未加载章节里的书签也能准确定位。PDF 可按页添加/取消书签，抽屉“书签”栏列出页码并可跳转、删除。
- 高亮与笔记：TXT/EPUB 正文支持选中文字，弹出菜单可高亮（黄/绿/粉三色）或写笔记；高亮和笔记以全文字符偏移存储，改字号、改窗口大小后位置不变。顶部“标注”入口打开独立标注页，列出全部高亮和笔记（含章节名与笔记内容），可跳回原文或删除。
- 阅读进度：滚动时节流保存（500ms），退出时保存；以“全书字符偏移”为锚点，重新打开同一本书会回到原位置。
- PDF 阅读：基于 pdfrx 渲染页面，支持缩放、上一页/下一页、输入页码跳转；读取 PDF 内嵌目录（书签）并在抽屉中展示，没有内嵌目录时按页跳转。PDF 进度以页码为锚点保存，重新打开回到原页。PDF 不写入章节表，不影响 TXT/EPUB 的章节目录。

## 环境要求

- Flutter 3.47.x（Dart 3.13.x）；本项目在 Flutter 3.47.9 / Dart 3.13.7 上验证。
- Windows 桌面端：
  - Visual Studio 2022，安装 “使用 C++ 的桌面开发” 工作负载。
  - 开启 Windows 开发者模式（设置 → 系统 → 开发者选项），插件构建需要符号链接支持。
- Android：
  - Android SDK（已验证 platform 36、build-tools 36.0.0、platform-tools、NDK 28.2.13676358）。
  - JDK 21。
  - 模拟器或真机（运行 `flutter devices` 确认）。

中国大陆网络下可设置镜像（可选）：

```bash
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
export PUB_HOSTED_URL=https://pub.flutter-io.cn
```

## 安装依赖

```bash
flutter pub get
```

PDF 渲染依赖 pdfrx，首次构建时由构建钩子从 GitHub 下载 PDFium 原生库。若 GitHub 不可达，构建会报 `build_hooks` 失败；可先用镜像下载对应平台的包，放到 `.dart_tool/hooks_runner/shared/pdfium_dart/build/chromium_8125/<平台>/`（Windows 为 `win-x64/pdfium.dll`）。本项目验证的是 `pdfium-win-x64.tgz`，来源为 `https://ghproxy.net/https://github.com/bblanchon/pdfium-binaries/releases/download/chromium%2F8125/pdfium-win-x64.tgz`。

只有修改了 Drift 表结构时才需要重新生成代码：

```bash
dart run build_runner build --delete-conflicting-outputs
```

Android 首次构建会下载 Gradle 与 Maven 依赖；若 `services.gradle.org` 超时，可手动把 `gradle-9.3.1-all.zip` 放入 `~/.gradle/wrapper/dists/gradle-9.3.1-all/<hash>/`，或把 `android/gradle/wrapper/gradle-wrapper.properties` 的 `distributionUrl` 指向可访问的镜像。

## 运行

```bash
flutter run -d windows
flutter run -d <android-device-id>
```

## 测试

```bash
flutter analyze
flutter test
```

当前状态：`flutter analyze` 无问题；`flutter test` 117 个测试全部通过。

构建验证（2026-11-03）：

- Windows：`flutter build windows --debug` 成功，可执行文件能正常启动。
- Android：`flutter build apk --debug` 成功，产物在 `build/app/outputs/flutter-apk/app-debug.apk`。当前机器没有模拟器或真机，安装、导入、续读等手动检查需要在设备上完成。

Android 构建备注：

- Flutter 要求 NDK 28.2.13676358；本项目使用命令行 SDK，NDK 已手动安装到 `F:/src/android-sdk/ndk/28.2.13676358`。
- 首次构建会下载 Gradle、Maven 依赖和 sqlite3 预编译库；网络受限时可使用镜像或手动缓存。
- 若 Windows 上出现 Kotlin 增量缓存关闭失败（`Could not close incremental caches`），已在 `android/gradle.properties` 中设置 `kotlin.incremental=false`。

## 手动验收清单

Windows（`flutter run -d windows`）或 Android 真机/模拟器：

1. 导入一个 UTF-8 中文 TXT 和一个 GB18030 中文 TXT，正文与目录正常。
2. 导入一个 EPUB，章节顺序与目录正常，正文可读。
3. 从目录跳到任意章节，上一章/下一章可用；左上角返回键能回到书架。
4. 给当前章节添加书签，在抽屉“书签”栏跳转和删除。
5. 选中一段正文，用黄/绿/粉任一颜色高亮；再选一段写笔记；从顶部“标注”页跳回原文并删除其中一条。
6. 高亮后调整字号/行距或改变窗口大小，高亮仍在原文字上；滚动到章节中部，关闭应用后重新打开同一本书，回到原段落。
7. 导入带内嵌目录的 PDF，打开后目录正确、点击目录能跳到对应页；翻到中间页退出重开，回到原页；缩放和输入页码跳转可用；在当前页添加书签，在抽屉“书签”栏跳转和删除。
8. 重复导入同一本书，出现「这本书已经在书架中」提示，书架不会多出一条。
9. 删除书籍后，书架条目和本地副本都消失。

## 已知限制（Phase 1）

- PDF 只读取内嵌目录；没有内嵌目录的 PDF 只能按页码跳转，不做自动生成目录。
- PDF 暂无高亮、笔记和选区标注（按当前范围决定暂不实现）；PDF 右键菜单为 pdfrx 默认的英文文案。
- EPUB 只提取纯文本，不还原 CSS、图片、封面等排版；同一 XHTML 文件内的多个小节会合并为一章。
- 扫描版 PDF 不做 OCR（后续按只读/占位处理）。
- TXT/EPUB 的高亮和笔记目前只能新增、查看、跳转和删除，暂不支持编辑内容或更换颜色。
- 暂无任何 AI 调用；`AssistantService` 等接口留到后续里程碑。
- 阅读设置（字号/行距/背景）仅在本次会话有效，未持久化。
- 阅读进度按字符偏移保存，用不同字号重新打开时可能落在相近但非完全相同的视觉位置。
﻿# git