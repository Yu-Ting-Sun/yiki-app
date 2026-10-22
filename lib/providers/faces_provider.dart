import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../core/api_client.dart';

/// 已註冊的家人臉譜：自拍（後端 face_store/ 的 enroll_<label>.raw）和
/// 相框鏡頭現場拍的（存在相框記憶卡上，後端只記張數）。
class FaceInfo {
  final String label;
  final int photoCount;
  final int cameraCount;

  const FaceInfo({
    required this.label,
    required this.photoCount,
    this.cameraCount = 0,
  });

  /// 「user（自拍 2・相框 8）」裡括號的部分。
  String get sourcesText {
    final parts = [
      if (photoCount > 0) '自拍 $photoCount',
      if (cameraCount > 0) '相框 $cameraCount',
    ];
    return parts.join('・');
  }
}

final facesProvider = FutureProvider.autoDispose<List<FaceInfo>>((ref) async {
  final dio = ref.watch(dioProvider);
  final res = await dio.get('/faces');
  return (res.data['faces'] as List? ?? [])
      .map((j) => FaceInfo(
            label: j['label'] as String,
            photoCount: j['photo_count'] as int? ?? 0,
            cameraCount: j['camera_count'] as int? ?? 0,
          ))
      .toList();
});

/// 請相框用自己的鏡頭幫 [label] 註冊：相框下次輪詢（10 秒內）就請站在
/// 前面的人看鏡頭，拍幾張存起來。跟辨識時同一支鏡頭，比自拍準。
Future<void> requestCameraEnroll(Dio dio, int frameId, String label) async {
  await dio.post('/frames/$frameId/camera-enroll', data: {'label': label});
}

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
