class Category {
  final String id;
  final String name;
  final String colorHex;
  final String iconName;
  final bool isDefault;

  const Category({
    required this.id,
    required this.name,
    required this.colorHex,
    required this.iconName,
    this.isDefault = false,
  });

  Category copyWith({
    String? id,
    String? name,
    String? colorHex,
    String? iconName,
    bool? isDefault,
  }) {
    return Category(
      id: id ?? this.id,
      name: name ?? this.name,
      colorHex: colorHex ?? this.colorHex,
      iconName: iconName ?? this.iconName,
      isDefault: isDefault ?? this.isDefault,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'colorHex': colorHex,
        'iconName': iconName,
        'isDefault': isDefault,
      };

  factory Category.fromJson(Map<String, dynamic> json) => Category(
        id: json['id'] as String,
        name: json['name'] as String,
        colorHex: json['colorHex'] as String,
        iconName: json['iconName'] as String,
        isDefault: json['isDefault'] as bool? ?? false,
      );
}
