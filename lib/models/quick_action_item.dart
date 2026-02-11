import 'package:flutter/material.dart';

class QuickActionItem {
  final String id;
  final String title;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const QuickActionItem({
    required this.id,
    required this.title,
    required this.icon,
    required this.color,
    this.onTap,
  });
}
