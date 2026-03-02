import 'package:flutter/material.dart';

class QuickActionItem {
  final String id;
  final String title;
  final IconData icon;
  final Color color;
  final String? valueText;
  final String? metaText;
  final VoidCallback? onTap;

  const QuickActionItem({
    required this.id,
    required this.title,
    required this.icon,
    required this.color,
    this.valueText,
    this.metaText,
    this.onTap,
  });
}
