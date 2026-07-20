import 'gps_point.dart';
import 'photo.dart';

/// GET /trips 清單裡的一筆旅程摘要。
class TripSummary {
  final int id;
  final String title;
  final DateTime? startTime;
  final DateTime? endTime;
  final double distanceM;
  final bool hasStory;
  final int pointCount;
  final int photoCount;
  final int? coverPhotoId;
  final DateTime createdAt;

  const TripSummary({
    required this.id,
    required this.title,
    this.startTime,
    this.endTime,
    required this.distanceM,
    required this.hasStory,
    required this.pointCount,
    required this.photoCount,
    this.coverPhotoId,
    required this.createdAt,
  });

  factory TripSummary.fromJson(Map<String, dynamic> json) => TripSummary(
        id: json['id'] as int,
        title: json['title'] as String? ?? '',
        startTime: json['start_time'] != null
            ? DateTime.parse(json['start_time'] as String)
            : null,
        endTime: json['end_time'] != null
            ? DateTime.parse(json['end_time'] as String)
            : null,
        distanceM: (json['distance_m'] as num?)?.toDouble() ?? 0,
        hasStory: json['has_story'] as bool? ?? false,
        pointCount: json['point_count'] as int? ?? 0,
        photoCount: json['photo_count'] as int? ?? 0,
        coverPhotoId: json['cover_photo_id'] as int?,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  /// 顯示用距離：<1000m 用公尺，其餘用公里。
  String get distanceLabel => distanceM < 1000
      ? '${distanceM.round()} 公尺'
      : '${(distanceM / 1000).toStringAsFixed(2)} 公里';
}

/// GET /trips/{id} 的完整旅程（含軌跡點、照片、遊記、參加者）。
class TripDetail {
  final TripSummary summary;
  final String storyText;

  /// 參加者（相框人臉辨識的 label，需與相框註冊名稱一致）。
  final List<String> members;
  final List<GpsPoint> points;
  final List<Photo> photos;

  const TripDetail({
    required this.summary,
    required this.storyText,
    required this.members,
    required this.points,
    required this.photos,
  });

  factory TripDetail.fromJson(Map<String, dynamic> json) => TripDetail(
        summary: TripSummary.fromJson(json),
        storyText: json['story_text'] as String? ?? '',
        members: (json['members'] as List? ?? [])
            .map((m) => m.toString())
            .toList(),
        points: (json['points'] as List? ?? [])
            .map((p) => GpsPoint.fromJson(p as Map<String, dynamic>))
            .toList(),
        photos: (json['photos'] as List? ?? [])
            .map((p) => Photo.fromJson(p as Map<String, dynamic>))
            .toList(),
      );
}
