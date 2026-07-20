import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../core/api_client.dart';

/// 已註冊的家人臉譜（後端 face_store/ 裡的 enroll_<label>.raw）。
class FaceInfo {
  final String label;
  final int photoCount;

  const FaceInfo({required this.label, required this.photoCount});
}

final facesProvider = FutureProvider.autoDispose<List<FaceInfo>>((ref) async {
  final dio = ref.watch(dioProvider);
  final res = await dio.get('/faces');
  return (res.data['faces'] as List? ?? [])
      .map((j) => FaceInfo(
            label: j['label'] as String,
            photoCount: j['photo_count'] as int? ?? 1,
          ))
      .toList();
});

/// 板端限制：檔名安全的英數字/底線/連字號、≤23 字元。
final faceLabelRe = RegExp(r'^[A-Za-z0-9_-]{1,23}$');

/// 上傳自拍註冊：後端轉成板端 photo-enroll 的 raw，相框同步後重開機生效。
Future<void> enrollFace(Dio dio, String label, List<XFile> photos) async {
  final form = FormData();
  form.fields.add(MapEntry('label', label));
  for (final p in photos) {
    form.files.add(MapEntry(
      'files',
      MultipartFile.fromBytes(await p.readAsBytes(), filename: p.name),
    ));
  }
  await dio.post(
    '/faces/enroll',
    data: form,
    options: Options(receiveTimeout: const Duration(seconds: 60)),
  );
}

Future<void> deleteFace(Dio dio, String label) async {
  await dio.delete('/faces/$label');
}
