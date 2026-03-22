# 看房日记 (House Viewing Diary)

一款基于 Flutter 的看房记录管理应用，帮助你记录和管理每次看房的详细信息，支持多平台运行。

## ✨ 功能特性

- **房源管理**：记录小区名称、地址、楼栋、房号、户型（室厅卫）、面积、价格等
- **看房状态**：待看、已看、感兴趣、已定、放弃
- **看房记录**：一套房可添加多条看房历史，记录每次看房的时间、状态和备注
- **标签系统**：支持边户、高层、电梯房、近地铁、采光好、南北通透等标签，可自定义
- **多媒体**：拍照/选图、录像，支持照片和视频预览
- **语音笔记**：录制语音备注，支持多段录音
- **地图定位**：集成高德地图，选点获取经纬度与地址（WebView 实现）
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
