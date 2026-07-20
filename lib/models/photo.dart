import '../core/constants.dart';

class Photo {
  final int id;
  final double? lat;
  final double? lng;
  final DateTime? timestamp;

  /// 後端回的相對路徑（例如 /photos/3）。
  final String url;

  const Photo({
    required this.id,
    this.lat,
    this.lng,
    this.timestamp,
    required this.url,
  });

  /// 給 Image.network 用的完整網址。
  String get fullUrl => '${AppConstants.apiBaseUrl}$url';

  factory Photo.fromJson(Map<String, dynamic> json) => Photo(
        id: json['id'] as int,
        lat: (json['lat'] as num?)?.toDouble(),
        lng: (json['lng'] as num?)?.toDouble(),
        timestamp: json['timestamp'] != null
            ? DateTime.parse(json['timestamp'] as String)
            : null,
        url: json['url'] as String,
      );
}
