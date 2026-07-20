import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_client.dart';
import '../models/spot.dart';

/// 旅程「收藏的景點」：記錄中在附近景點按 ➕ 加進來的清單。
/// GET /trips/{id}/spots/saved
final savedSpotsProvider =
    FutureProvider.autoDispose.family<List<Spot>, int>((ref, tripId) async {
  final dio = ref.watch(dioProvider);
  final res = await dio.get('/trips/$tripId/spots/saved');
  final list = (res.data['spots'] as List? ?? []);
  return list.map((j) => Spot.fromJson(j as Map<String, dynamic>)).toList();
});

/// 把附近景點收藏進旅程。回傳是否為重複收藏。
Future<bool> saveSpotToTrip(Dio dio, int tripId, Spot s) async {
  final res = await dio.post('/trips/$tripId/spots/save', data: {
    'name': s.name,
    'lat': s.lat,
    'lng': s.lng,
    'category': s.category,
    'description': s.description,
  });
  return res.data['duplicate'] as bool? ?? false;
}

/// 移除一筆收藏。
Future<void> removeSavedSpot(Dio dio, int tripId, int spotId) async {
  await dio.delete('/trips/$tripId/spots/saved/$spotId');
}

/// 記錄中的「附近有什麼」：以目前位置查 GET /spots/nearby。
/// 兩段式：describe=false 先快回清單，再帶 describe=true 補 AI 介紹
/// （後端有 ~100m 網格快取，第二段只跑 LLM 不重打 Overpass）。
Future<List<Spot>> fetchNearbySpots(
  Dio dio,
  double lat,
  double lng, {
  bool describe = false,
  bool refresh = false,
}) async {
  final res = await dio.get(
    '/spots/nearby',
    queryParameters: {
      'lat': lat,
      'lng': lng,
      if (describe) 'describe': 'true',
      if (refresh) 'refresh': 'true',
    },
    options: Options(receiveTimeout: const Duration(seconds: 40)),
  );
  final list = (res.data['spots'] as List? ?? []);
  return list.map((j) => Spot.fromJson(j as Map<String, dynamic>)).toList();
}
