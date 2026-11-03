# hackathon_reading

一个面向 Windows 和 Android 的本地阅读器（Flutter），为后续的 AI 陪读、AI 翻译、划重点解读预留接口。当前为 **Phase 1：TXT 阅读闭环**。

## 已实现（Phase 1）

- 书架：导入、展示、删除书籍，本地保存副本。
- 导入格式：TXT、EPUB、PDF。**目前只有 TXT 会被解析并阅读**；EPUB/PDF 先作为书架条目保存，阅读器在后续里程碑实现。
- TXT 编码自动识别：UTF-8（含 BOM）、UTF-16 LE/BE（含 BOM）、GB18030/GBK/GB2312；无法严格解码时按 UTF-8 容错处理。
- 章节识别：基于行首标题规则（`第X章/节/卷/回/部/篇/集`、序章、楔子、前言、番外、`Chapter N` 等），无标题时整本书作为一章；误判控制：过长的行或句末带标点的行不会当作标题。
- 阅读器：目录抽屉跳章、上一章/下一章、字号 14–28、行距 1.2–2.0、浅色/米色/深色背景（本次会话内生效）；正文按章节懒加载，调整字号或窗口大小后会保持在原阅读位置。
- 阅读进度：滚动时节流保存（500ms），退出时保存；以“全书字符偏移”为锚点，重新打开同一本书会回到原位置。

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

当前状态：`flutter analyze` 无问题；`flutter test` 51 个测试全部通过。

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
2. 从目录跳到任意章节，上一章/下一章可用。
3. 滚动到章节中部，关闭应用后重新打开同一本书，回到原段落。
4. 调整字号/行距，当前阅读位置不丢失。
5. 删除书籍后，书架条目和本地副本都消失。

## 已知限制（Phase 1）

- EPUB/PDF 只能导入书架，不能打开阅读；EPUB/PDF 的目录解析尚未实现。
- 扫描版 PDF 不做 OCR（后续按只读/占位处理）。
- 暂无标注、书签、高亮、笔记。
- 暂无任何 AI 调用；`AssistantService` 等接口留到后续里程碑。
- 阅读设置（字号/行距/背景）仅在本次会话有效，未持久化。
- 阅读进度按字符偏移保存，用不同字号重新打开时可能落在相近但非完全相同的视觉位置。
