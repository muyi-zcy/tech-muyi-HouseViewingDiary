import 'package:flutter/material.dart';

import 'local_media_preview_stub.dart' if (dart.library.io) 'local_media_preview_io.dart' as impl;

/// 全屏预览本地图片（缩放）或视频（内置播放器）。Web 上提示不支持。
Future<void> showLocalMediaPreview(BuildContext context, String path) {
  return impl.showLocalMediaPreview(context, path);
}
