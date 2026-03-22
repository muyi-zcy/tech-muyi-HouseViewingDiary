import 'package:flutter/widgets.dart';

import 'file_image_widget_stub.dart'
    if (dart.library.io) 'file_image_widget_io.dart' as impl;

/// 非 Web 用 [Image.file]，Web 用占位（与 RN 相册预览在 Flutter Web 的限制一致）。
Widget fileImageOrPlaceholder(String path, {double width = 70, double height = 70}) {
  return impl.build(path, width, height);
}
