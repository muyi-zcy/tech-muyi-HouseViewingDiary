import 'package:flutter/material.dart';

Widget build(String path, double width, double height) {
  return Container(
    width: width,
    height: height,
    color: const Color(0xFFE8E8EB),
    child: const Icon(Icons.image_outlined, color: Color(0xFFB2BEC3), size: 28),
  );
}
