class GpsPoint {
  final double lat;
  final double lng;
  final DateTime timestamp;

  const GpsPoint({required this.lat, required this.lng, required this.timestamp});

  factory GpsPoint.fromJson(Map<String, dynamic> json) => GpsPoint(
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
        timestamp: DateTime.parse(json['timestamp'] as String),
      );

  Map<String, dynamic> toJson() => {
        'lat': lat,
        'lng': lng,
        'timestamp': timestamp.toUtc().toIso8601String(),
      };
}
