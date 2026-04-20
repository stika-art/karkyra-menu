import 'package:flutter/material.dart';

class Category {
  final String id;
  final String title;
  final IconData? icon;
  final String? emoji;

  Category({
    required this.id,
    required this.title,
    this.icon,
    this.emoji,
  });
}
