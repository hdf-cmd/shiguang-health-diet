// ShiguangFlutter/lib/features/common/sheet.dart
// M9-B4：弹层样板收口（10 处 showModalBottomSheet 的 shape/背景/标题行+✕
// 复制收敛；顶部 drag handle；isScrollControlled+最大高 78%）。
// ✕ 钮结构与标题文本逐字保留——既有测试选择器零破坏是收口底线。
// [closeKey]：简报签名的**登记扩展**（T9 续正，T8 评审 minor）——既有测试
// find.byKey 点 ✕ 实际引用的只有 goal_sheet/water_card 的 goalCloseKey 与
// goal_edit 的 goalEditCloseKey（H5 id 同名键）；exercise 的 ex-close 与
// custom_food 的 sheet-close 两键测试零引用（grep 为空），键位保留系
// H5 id 平齐，非测试依赖。收口后键位由 helper 承载，各层原键常量原样
// 透传，测试选择器零改动。
import 'package:flutter/material.dart';

import '../../app/theme.dart';

Future<T?> showShiguangSheet<T>(
  BuildContext context, {
  required String title,
  required Widget child,
  Key? closeKey,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Tokens.surface,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
            top: Radius.circular(Tokens.radiusSheet))),
    builder: (ctx) => LayoutBuilder(
      // M9-T8 对简报的登记偏差①：78% 上限的基准高度取「路由传入约束」而非
      // MediaQuery.sizeOf——真机上二者同为屏高，语义等价；但测试环境里
      // harness.useBigSurface 的 setSurfaceSize 只改渲染面不改 MediaQuery
      // （MediaQuery 恒 800×600），按 MediaQuery 取 78% 会把 1600 高画布上的
      // 弹层腰斩到 468，长表单（custom_food ③）视口 415 引发焦点回滚与
      // ensureVisible 互斥。maxHeight 非有限时回落 MediaQuery×0.78。
      builder: (ctx, constraints) => ConstrainedBox(
        constraints: BoxConstraints(
            maxHeight: constraints.maxHeight.isFinite
                ? constraints.maxHeight * 0.78
                : MediaQuery.sizeOf(ctx).height * 0.78),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(
                    top: Tokens.sp2, bottom: Tokens.sp1),
                width: 28,
                height: 4,
                decoration: BoxDecoration(
                    color: Tokens.surfaceSoft,
                    borderRadius: BorderRadius.circular(2)), // drag handle
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    Tokens.sp5, Tokens.sp2, Tokens.sp5, 0),
                child: Row(
                  children: [
                    Expanded(
                        child: Text(
                      title,
                      style: const TextStyle(
                          fontSize: Tokens.textLg,
                          fontWeight: FontWeight.w800,
                          color: Tokens.ink),
                    )),
                    Semantics(
                      label: '关闭',
                      button: true,
                      child: GestureDetector(
                        key: closeKey,
                        onTap: () => Navigator.of(ctx).pop(),
                        child: const Padding(
                          padding: EdgeInsets.all(Tokens.sp1),
                          child: Text('✕',
                              style: TextStyle(
                                  fontSize: Tokens.textMd,
                                  color: Tokens.ink3)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Flexible(child: child),
            ],
          ),
        ),
      ),
    ),
  );
}
