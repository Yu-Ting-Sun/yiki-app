import 'dart:typed_data';

import 'package:exif/exif.dart';

/// 從 EXIF 讀拍攝時間（"2026:07:09 10:30:00" 格式，手機當地時間）；
/// 沒有就回 null。補上傳舊照片時用它讓照片落在軌跡時間軸的正確位置。
Future<DateTime?> exifDateTime(Uint8List bytes) async {
  try {
    final tags = await readExifFromBytes(bytes);
    for (final key in ['EXIF DateTimeOriginal', 'Image DateTime']) {
      final v = tags[key]?.printable;
      if (v == null) continue;
      final m = RegExp(r'^(\d{4}):(\d{2}):(\d{2})[ T](\d{2}):(\d{2}):(\d{2})')
          .firstMatch(v.trim());
      if (m == null) continue;
      return DateTime(
        int.parse(m[1]!),
        int.parse(m[2]!),
        int.parse(m[3]!),
        int.parse(m[4]!),
        int.parse(m[5]!),
        int.parse(m[6]!),
      );
    }
  } catch (_) {}
  return null;
}

/// 從相簿照片的 EXIF 讀 GPS 座標；沒有 GPS 資訊回 null。
Future<({double lat, double lng})?> exifLatLng(Uint8List bytes) async {
  try {
    final tags = await readExifFromBytes(bytes);
    final latTag = tags['GPS GPSLatitude'];
    final lngTag = tags['GPS GPSLongitude'];
    if (latTag == null || lngTag == null) return null;

    double toDouble(dynamic v) =>
        v is Ratio ? v.numerator / v.denominator : (v as num).toDouble();

    double dms(IfdTag tag) {
      final v = tag.values.toList();
      return toDouble(v[0]) + toDouble(v[1]) / 60 + toDouble(v[2]) / 3600;
    }

    var lat = dms(latTag);
    var lng = dms(lngTag);
    if (tags['GPS GPSLatitudeRef']?.printable == 'S') lat = -lat;
    if (tags['GPS GPSLongitudeRef']?.printable == 'W') lng = -lng;
    return (lat: lat, lng: lng);
  } catch (_) {
    return null; // EXIF 壞掉就當沒有座標
  }
}
