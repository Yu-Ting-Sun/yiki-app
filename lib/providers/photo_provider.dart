import 'dart:typed_data';

import 'package:dio/dio.dart';

/// multipart 上傳一張照片到 POST /trips/{id}/photos。
/// 失敗丟 DioException，由呼叫端顯示錯誤與重試按鈕。
Future<void> uploadTripPhoto({
  required Dio dio,
  required int tripId,
  required Uint8List bytes,
  required String filename,
  double? lat,
  double? lng,
  DateTime? timestamp,
}) async {
  final form = FormData.fromMap({
    'file': MultipartFile.fromBytes(bytes, filename: filename),
    if (lat != null) 'lat': lat.toString(),
    if (lng != null) 'lng': lng.toString(),
    if (timestamp != null) 'timestamp': timestamp.toUtc().toIso8601String(),
  });
  await dio.post('/trips/$tripId/photos', data: form);
}
