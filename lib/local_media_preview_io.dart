import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

bool _isVideoPath(String path) {
  final lowered = path.toLowerCase();
  return lowered.endsWith('.mp4') ||
      lowered.endsWith('.mov') ||
      lowered.endsWith('.m4v') ||
      lowered.endsWith('.webm') ||
      lowered.endsWith('.avi') ||
      lowered.endsWith('.mkv');
}

Future<void> showLocalMediaPreview(BuildContext context, String path) async {
  if (!context.mounted) return;
  if (!File(path).existsSync()) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('文件不存在或已被移动')),
    );
    return;
  }
  if (_isVideoPath(path)) {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => _VideoPreviewScreen(path: path),
        fullscreenDialog: true,
      ),
    );
    return;
  }
  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.black87,
    builder: (dialogContext) {
      return GestureDetector(
        onTap: () => Navigator.of(dialogContext).pop(),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            child: Stack(
              children: [
                Center(
                  child: InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 4,
                    child: Image.file(File(path), fit: BoxFit.contain),
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: IconButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _VideoPreviewScreen extends StatefulWidget {
  const _VideoPreviewScreen({required this.path});

  final String path;

  @override
  State<_VideoPreviewScreen> createState() => _VideoPreviewScreenState();
}

class _VideoPreviewScreenState extends State<_VideoPreviewScreen> {
  late final VideoPlayerController _controller;
  bool _ready = false;
  String? _error;

  Future<void> _initVideo() async {
    try {
      await _controller.initialize();
      if (mounted) setState(() => _ready = true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(File(widget.path));
    _controller.addListener(() {
      if (mounted) setState(() {});
    });
    unawaited(_initVideo());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('视频预览'),
      ),
      body: Center(
        child: _error != null
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error!, style: const TextStyle(color: Colors.white70), textAlign: TextAlign.center),
              )
            : !_ready
                ? const CircularProgressIndicator(color: Colors.white70)
                : AspectRatio(
                    aspectRatio: _controller.value.aspectRatio == 0 ? 16 / 9 : _controller.value.aspectRatio,
                    child: VideoPlayer(_controller),
                  ),
      ),
      floatingActionButton: _ready && _error == null
          ? FloatingActionButton(
              onPressed: () {
                if (_controller.value.isPlaying) {
                  _controller.pause();
                } else {
                  _controller.play();
                }
                setState(() {});
              },
              backgroundColor: Colors.white24,
              child: Icon(_controller.value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
            )
          : null,
    );
  }
}
