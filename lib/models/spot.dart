/// 景點。category 是後端給的中文分類（餐廳/咖啡廳/古蹟/景點…）；
/// id 只有「收藏進旅程」的景點才有（刪收藏要用）。
class Spot {
  final int? id;
  final String name;
  final double lat;
  final double lng;
  final double distanceM;
  final String category;
  final String description;

  const Spot({
    this.id,
    required this.name,
    required this.lat,
    required this.lng,
    required this.distanceM,
    required this.category,
    required this.description,
  });

  factory Spot.fromJson(Map<String, dynamic> json) => Spot(
        id: json['id'] as int?,
        name: json['name'] as String,
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
        distanceM: (json['distance_m'] as num?)?.toDouble() ?? 0,
        category: json['category'] as String? ?? '',
        description: json['description'] as String? ?? '',
      );

  static const _foodCategories = {
    '餐廳', '美食廣場', '咖啡廳', '小吃', '酒吧', '居酒屋', '冰品', '市場', '烘焙坊',
  };

  /// 美食類（用來給標籤上色、選 icon）。
  bool get isFood => _foodCategories.contains(category);

  String get distanceLabel => distanceM < 1000
      ? '離路線約 ${distanceM.round()} 公尺'
      : '離路線約 ${(distanceM / 1000).toStringAsFixed(1)} 公里';
}
