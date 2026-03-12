import 'package:flutter/material.dart';

const Map<String, IconData> categoryIcons = {
  'restaurant': Icons.restaurant,
  'directions_car': Icons.directions_car,
  'movie': Icons.movie,
  'local_hospital': Icons.local_hospital,
  'shopping_bag': Icons.shopping_bag,
  'home': Icons.home,
  'school': Icons.school,
  'more_horiz': Icons.more_horiz,
  'attach_money': Icons.attach_money,
  'sports': Icons.sports,
  'flight': Icons.flight,
  'pets': Icons.pets,
  'phone': Icons.phone,
  'fitness_center': Icons.fitness_center,
  'coffee': Icons.coffee,
};

// Curated generic icons shown in category pickers.
const List<String> reservedCategoryIcons = [
  'more_horiz',
  'attach_money',
  'coffee',
  'home',
  'shopping_bag',
  'fitness_center',
  'sports',
  'flight',
  'phone',
  'pets',
  'school',
  'restaurant',
];

IconData iconFromName(String name) => categoryIcons[name] ?? Icons.category;
