# 看房日记 (House Viewing Diary)

一款基于 Flutter 的看房记录管理应用，帮助你记录和管理每次看房的详细信息，支持多平台运行。

## 📖 发布说明（v1.0.0）

### 产品简介

**看房日记**面向购房、租房人群，用一套房源档案串联信息整理、多次看房、状态跟进与地图回顾。数据保存在本机，不依赖账号与云端，适合带看、比价阶段长期使用。

### 核心功能

- **房源档案**：小区、地址、楼栋与房号、户型（室/厅/卫）、面积、价格等；经纪人姓名与电话，支持一键拨号。
- **看房状态**：待看、已看、感兴趣、已定、放弃，便于筛选与复盘。
- **看房历史**：同一房源可追加多条记录，分别记录时间、状态与文字备注，形成时间线。
- **标签体系**：内置常用标签，支持自定义，便于对比与过滤。
- **多媒体与语音**：拍照、相册选图、录像与本地预览；多段语音备注与回放。
- **地图与定位**：高德地图 Web 选点，回填经纬度与地址；**地图**页展示已保存位置的房源，点击标记可查看摘要并进入详情或编辑。
- **分享文案解析**：粘贴安居客、贝壳等分享文案或链接，解析户型、面积、价格等；有链接时可尝试拉取网页补充空白字段（需网络，用户主动触发）。
- **统计概览**：房源总数、各状态数量及「已定/总记录」占比。
- **界面结构**：底部三栏 **看房记录**、**统计**、**地图**，Material 3 与新拟态风格。

### 数据与隐私

数据通过本机 **SharedPreferences** 持久化，日常以本地为主；分享解析若访问房源网页会发起网络请求，属用户主动操作。

### 版本与平台

当前版本见 `pubspec.yaml`（如 `1.0.0+1`）。技术栈为 Flutter，支持 Android、iOS、Web、Windows 等（以实际构建目标为准）。

## ✨ 功能特性

- **房源管理**：记录小区名称、地址、楼栋、房号、户型（室厅卫）、面积、价格等
- **看房状态**：待看、已看、感兴趣、已定、放弃
- **看房记录**：一套房可添加多条看房历史，记录每次看房的时间、状态和备注
- **标签系统**：支持边户、高层、电梯房、近地铁、采光好、南北通透等标签，可自定义
- **多媒体**：拍照/选图、录像，支持照片和视频预览
- **语音笔记**：录制语音备注，支持多段录音
- **地图定位**：集成高德地图，选点获取经纬度与地址（WebView 实现）；地图页展示房源标记与摘要
- **统计**：总记录数、各状态分布、已定占比
- **分享解析**：粘贴平台分享文案或链接，自动解析并可选网页补全（`listing_share_parser`）
- **经纪人信息**：记录中介姓名、电话，支持一键拨号
- **数据持久化**：本地存储（SharedPreferences），数据不依赖网络

## 🛠 技术栈

| 依赖 | 用途 |
|------|------|
| `shared_preferences` | 本地数据存储 |
| `uuid` | 记录唯一标识 |
| `image_picker` | 拍照 / 相册选图 |
| `webview_flutter` | 内嵌高德地图 Web 页 |
| `flutter_dotenv` | 环境变量（地图 Key） |
| `geolocator` | 定位服务 |
| `record` / `just_audio` | 录音与播放 |
| `video_player` | 视频预览 |
| `path_provider` | 本地文件路径 |
| `url_launcher` | 拨号、打开链接 |
| `http` | 分享链接网页补全等网络请求 |

## 🎨 应用图标与 Logo

- 资源路径：`assets/images/logo.jpg`（首页标题旁展示）
- 更新桌面图标：修改该图后执行  
  `dart run flutter_launcher_icons`  
  会按 `pubspec.yaml` 中的 `flutter_launcher_icons` 配置生成 Android / iOS 启动图标。

## 📋 环境要求

- Flutter SDK ^3.10.8
- Dart ^3.10.8

## 🚀 快速开始

### 1. 克隆与安装

```bash
git clone <repository-url>
cd HouseViewingDiary
flutter pub get
```

### 2. 配置高德地图 Key（可选）

地图功能需要高德 Web 服务 Key，任选其一配置：

**方式 A：环境文件**

在 `assets/` 目录下创建 `amap.env` 文件：

```
AMAP_KEY=你的高德Web服务Key
AMAP_SECURITY_JSCODE=你的安全密钥（可选，用于 Web 端）
```

**方式 B：构建参数**

```bash
flutter run --dart-define=AMAP_KEY=你的Key
# 或 Web 端需要安全密钥时：
flutter run -d chrome --dart-define=AMAP_KEY=xxx --dart-define=AMAP_SECURITY_JSCODE=xxx
```

> 未配置时，地图选点功能可能受限，其他功能可正常使用。

### 3. 运行

```bash
# 默认设备
flutter run

# 指定平台
flutter run -d chrome    # Web
flutter run -d windows   # Windows
flutter run -d android   # Android
flutter run -d ios       # iOS
```

## 📱 支持平台

- Android  
- iOS  
- Web  
- Windows  
- Linux  
- macOS  

## 📁 项目结构

```
lib/
├── main.dart              # 主入口、数据模型、核心 UI
├── listing_share_parser.dart # 分享文案 / 链接解析
├── amap/                  # 高德地图相关
│   ├── amap_config.dart   # Key 配置
│   ├── amap_web_page.dart # 地图 WebView 页
│   ├── current_location.dart
│   └── webview_init_*.dart
├── file_image_widget*.dart   # 本地图片/视频组件
├── local_media_preview*.dart # 媒体预览
└── voice_note_dir*.dart      # 语音笔记目录
```

## 📄 数据模型

- **HouseViewing**：房源（小区、户型、价格、经纪人等）
- **ViewingHistoryEntry**：单次看房记录（时间、状态、备注、录音、照片）
- **ViewStatus**：看房状态枚举

数据以 JSON 形式存储在 `SharedPreferences` 中，首次启动会生成示例数据。

## 👤 开发者

全平台账号：**沐乙师傅还不收工**，欢迎关注。

## 📜 许可证

本项目采用 MIT 许可证开源，详见 [LICENSE](LICENSE) 文件。
