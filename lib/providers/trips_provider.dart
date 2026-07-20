import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_client.dart';
import '../models/trip.dart';

/// GET /trips → 旅程摘要清單（新的在前，後端已排序）。
/// 下拉重新整理用 ref.refresh(tripsProvider.future)。
final tripsProvider = FutureProvider<List<TripSummary>>((ref) async {
  final dio = ref.watch(dioProvider);
  final res = await dio.get('/trips');
  final list = (res.data['trips'] as List? ?? []);
  return list
      .map((j) => TripSummary.fromJson(j as Map<String, dynamic>))
      .toList();
});

/// GET /trips/{id} → 單一旅程詳情。
final tripDetailProvider =
    FutureProvider.family<TripDetail, int>((ref, tripId) async {
  final dio = ref.watch(dioProvider);
  final res = await dio.get('/trips/$tripId');
  return TripDetail.fromJson(res.data as Map<String, dynamic>);
});

