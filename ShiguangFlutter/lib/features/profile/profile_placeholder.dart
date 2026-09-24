// ShiguangFlutter/lib/features/profile/profile_placeholder.dart
import 'package:flutter/material.dart';

class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen(this.title, {super.key});
  final String title;
  @override
  Widget build(BuildContext context) => Center(child: Text(title));
}
