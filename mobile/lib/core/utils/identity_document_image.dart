import 'dart:convert';
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

class IdentityDocumentImage {
  const IdentityDocumentImage({required this.bytes, required this.mimeType});

  final Uint8List bytes;
  final String mimeType;

  String get dataUrl => 'data:$mimeType;base64,${base64Encode(bytes)}';
}

Future<IdentityDocumentImage?> pickIdentityDocumentImage() async {
  final XFile? file = await ImagePicker().pickImage(
    source: ImageSource.gallery,
    maxWidth: 1600,
    imageQuality: 80,
  );
  if (file == null) return null;

  final String extension = file.name.split('.').last.toLowerCase();
  final String mimeType = switch (extension) {
    'png' => 'image/png',
    'webp' => 'image/webp',
    'jpg' || 'jpeg' => 'image/jpeg',
    _ => file.mimeType ?? '',
  };
  if (!const <String>{'image/jpeg', 'image/png', 'image/webp'}.contains(mimeType)) {
    throw const FormatException('فقط تصویر JPEG، PNG یا WebP قابل ارسال است.');
  }

  final Uint8List bytes = await file.readAsBytes();
  if (bytes.isEmpty || bytes.length > 5 * 1024 * 1024) {
    throw const FormatException('حجم تصویر باید حداکثر ۵ مگابایت باشد.');
  }
  return IdentityDocumentImage(bytes: bytes, mimeType: mimeType);
}
