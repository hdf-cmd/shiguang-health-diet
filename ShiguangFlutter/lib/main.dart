// ShiguangFlutter/lib/main.dart
import 'package:flutter/material.dart';
import 'app/shell.dart';
import 'app/theme.dart';

void main() => runApp(const ShiguangApp());

class ShiguangApp extends StatelessWidget {
  const ShiguangApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: '食光',
        theme: shiguangTheme(),
        home: const Shell(),
      );
}
