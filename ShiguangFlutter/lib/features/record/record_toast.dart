// 记录成功的提示胶囊。
// SnackBar 挂在根 ScaffoldMessenger 上，会被 showModalBottomSheet 的弹层整块盖住；
// 4s 固定底栏还能在关层后残留、压住「记一笔」。这里改用根 Overlay 悬浮 1.2s 胶囊，
// 始终在弹层之上、IgnorePointer 不拦点击，位置抬高让出底部按钮。
import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/theme.dart';

const Duration kAddedToastDuration = Duration(milliseconds: 1200);

OverlayEntry? _active;
Timer? _timer;

void showAddedToast(OverlayState overlay, String text) {
  _timer?.cancel();
  _timer = null;
  _active?.remove();
  _active = null;

  late final OverlayEntry entry;
  entry = OverlayEntry(builder: (ctx) {
    final media = MediaQuery.of(ctx);
    return Positioned(
      left: Tokens.sp4,
      right: Tokens.sp4,
      bottom: media.padding.bottom + 240,
      child: IgnorePointer(
        child: Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: Tokens.sp4, vertical: Tokens.sp3),
              decoration: BoxDecoration(
                color: Tokens.ink,
                borderRadius: BorderRadius.circular(Tokens.radiusLg),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 16,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Text(
                text,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: Tokens.textSm,
                    fontWeight: FontWeight.w600,
                    color: Colors.white),
              ),
            ),
          ),
        ),
      ),
    );
  });

  _active = entry;
  overlay.insert(entry);
  _timer = Timer(kAddedToastDuration, () {
    if (!identical(_active, entry)) return;
    _active = null;
    try {
      entry.remove();
    } catch (_) {
      // overlay 已随页面销毁，忽略
    }
  });
}
