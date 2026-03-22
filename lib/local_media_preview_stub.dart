import 'package:flutter/material.dart';

Future<void> showLocalMediaPreview(BuildContext context, String path) async {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('当前平台不支持本地文件预览')),
  );
}
