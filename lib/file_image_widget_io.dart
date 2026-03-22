import 'dart:io';

import 'package:flutter/material.dart';

Widget build(String path, double width, double height) {
  return Image.file(
    File(path),
    width: width,
    height: height,
    fit: BoxFit.cover,
    errorBuilder: (context, o, s) => Container(
      width: width,
      height: height,
      color: const Color(0xFFE8E8EB),
      child: const Icon(Icons.broken_image_outlined, color: Color(0xFFB2BEC3)),
    ),
  );
}
