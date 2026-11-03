# 在没有开启 Windows 开发者模式的机器上，让 `flutter build windows` 绕开插件符号链接检查。
#
# 背景：flutter_tools 会为每个插件在 windows/flutter/ephemeral/.plugin_symlinks/ 下建符号链接。
# 创建符号链接需要开发者模式或管理员权限，否则构建直接报
#   "Building with plugins requires symlink support."
# 目录联接（junction）不需要这些权限，而且 flutter_tools 检测到链接已存在且指向正确时会直接跳过创建。
#
# 用法（在仓库根目录）：pwsh -File tool/plugin_symlinks.ps1
# 时机：`flutter pub get` 之后、`flutter build windows` 之前；依赖变化后需要重跑。
# 注意：`flutter pub get` 会先删除整个 .plugin_symlinks 目录，所以它失败之后再跑本脚本即可。

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$depsPath = Join-Path $root '.flutter-plugins-dependencies'
if (-not (Test-Path $depsPath)) {
  throw "找不到 $depsPath，请先运行 flutter pub get（它失败也没关系，只要写出了依赖清单）。"
}

$deps = Get-Content $depsPath -Raw | ConvertFrom-Json
$windows = $deps.plugins.windows
if (-not $windows) {
  Write-Host '没有 Windows 插件，无需处理。'
  exit 0
}

$linkDir = Join-Path $root 'windows\flutter\ephemeral\.plugin_symlinks'
New-Item -ItemType Directory -Force -Path $linkDir | Out-Null

foreach ($plugin in $windows) {
  $target = ($plugin.path -replace '\\\\', '\').TrimEnd('\')
  $link = Join-Path $linkDir $plugin.name
  if (Test-Path $link) {
    Write-Host ("已存在：{0}" -f $plugin.name)
    continue
  }
  New-Item -ItemType Junction -Path $link -Target $target | Out-Null
  Write-Host ("联接 {0} -> {1}" -f $plugin.name, $target)
}

Write-Host '完成。现在可以用 flutter build windows --no-pub 构建。'
