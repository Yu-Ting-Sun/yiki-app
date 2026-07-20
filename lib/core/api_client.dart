import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'constants.dart';

/// 全 App 共用的 dio 實例；base URL 見 constants.dart。
final dioProvider = Provider<Dio>((ref) {
  return Dio(
    BaseOptions(
      baseUrl: AppConstants.apiBaseUrl,
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 30),
    ),
  );
});

/// 把 DioException 轉成使用者看得懂的訊息（顯示在 SnackBar）。
String friendlyError(Object error) {
  if (error is DioException) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.connectionError:
        return '連不到伺服器，請確認手機跟電腦在同一個 Wi-Fi，'
            '且後端已啟動（${AppConstants.apiBaseUrl}）';
      case DioExceptionType.receiveTimeout:
        return '伺服器回應逾時，請稍後再試';
      case DioExceptionType.badResponse:
        final code = error.response?.statusCode;
        final detail = error.response?.data is Map
            ? (error.response!.data as Map)['detail']
            : null;
        return '伺服器錯誤（$code）${detail != null ? '：$detail' : ''}';
      default:
        return '網路錯誤：${error.message}';
    }
  }
  return '發生錯誤：$error';
}
