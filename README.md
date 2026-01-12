# Oblivion Launcher

一个类 Material Design 3 风格的 Minecraft 启动器。

由夏湖團隊开发。

__对虽然只有我一个人。__

## 这是什么

一个简单的 Minecraft 启动器，支持多版本管理、模组下载、账号切换等基本功能，后续将会完善。

## 主要功能

- 游戏版本管理：下载、安装、删除各种 Minecraft 版本
- 模组管理：支持从 Modrinth 和 CurseForge 搜索下载模组
- 账号管理：支持离线账号和正版账号
- Java 管理：自动检测系统 Java，也可以手动指定
- 下载管理：多线程下载，支持断点续传

## 技术栈

本项目使用 Flutter 进行开发。

## 构建说明

### 环境要求

- Flutter SDK 3.38.6 或更高版本
- Dart SDK 3.5.0 或更高版本

### 构建步骤

装好 Flutter SDK，然后：

```bash
cd oblivion_launcher
flutter pub get
flutter build windows --release
```

构建产物在 `build/windows/x64/runner/Release/` 目录下。

## 许可证

本项目采用 GPL 3.0 许可证。详见 [LICENSE](LICENSE) 文件。

## 社区

加入我们：1005102809

你可以向我提交 issues, pull requests 和建议，我鼓励进行二次创作/交流讨论。