import 'dart:io';

Future<void> ensureVoiceNotesDirectory(String documentsPath) async {
  final d = Directory('$documentsPath/voice_notes');
  if (!await d.exists()) await d.create(recursive: true);
}
