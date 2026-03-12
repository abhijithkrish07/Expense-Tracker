class Budget {
  final String id;
  final int year;
  final int month;
  final double limitAmount;
  final String? categoryId;

  const Budget({
    required this.id,
    required this.year,
    required this.month,
    required this.limitAmount,
    this.categoryId,
  });

  Budget copyWith({
    String? id,
    int? year,
    int? month,
    double? limitAmount,
    String? categoryId,
  }) {
    return Budget(
      id: id ?? this.id,
      year: year ?? this.year,
      month: month ?? this.month,
      limitAmount: limitAmount ?? this.limitAmount,
      categoryId: categoryId ?? this.categoryId,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'year': year,
        'month': month,
        'limitAmount': limitAmount,
        'categoryId': categoryId,
      };

  factory Budget.fromJson(Map<String, dynamic> json) => Budget(
        id: json['id'] as String,
        year: json['year'] as int,
        month: json['month'] as int,
        limitAmount: (json['limitAmount'] as num).toDouble(),
        categoryId: json['categoryId'] as String?,
      );
}
