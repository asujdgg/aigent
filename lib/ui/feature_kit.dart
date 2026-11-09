import 'package:flutter/material.dart';
import '../i18n.dart';
import '../theme.dart';

/// 新功能页共用的视觉件：与设置页同款顶栏、纸片卡片、主按钮。
/// 单独抽出来是为了两个新页面长得像同一个产品里的功能，
/// 也避免把设置页那套 100KB 的私有组件复制两遍。

Widget featureRoundButton(bool dark, IconData icon, VoidCallback onPressed,
    {String? tooltip, Color? color}) {
  final btn = Container(
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: dark ? Colors.white.withOpacity(0.045) : Colors.black.withOpacity(0.015),
      border: Border.all(color: hairOf(dark), width: 0.7),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(dark ? 0.30 : 0.055),
          blurRadius: 9,
          offset: const Offset(0, 1.4),
        ),
      ],
    ),
    child: Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        splashColor: (dark ? Colors.white : Colors.black).withOpacity(0.04),
        highlightColor: Colors.transparent,
        child: SizedBox(
          width: 38,
          height: 38,
          child: Icon(icon, size: 19, color: color ?? (dark ? C.dInk2 : C.ink2)),
        ),
      ),
    ),
  );
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
    child: tooltip == null ? btn : Tooltip(message: tooltip, child: btn),
  );
}

PreferredSizeWidget featureAppBar(
  BuildContext context,
  bool dark, {
  required String title,
  List<Widget>? actions,
}) {
  return AppBar(
    centerTitle: true,
    backgroundColor: canvasOf(dark),
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    scrolledUnderElevation: 0,
    title: Text(title,
        style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w600)),
    leading: featureRoundButton(dark, Icons.arrow_back_rounded,
        () => Navigator.maybePop(context),
        tooltip: t('返回')),
    actions: actions ?? const [SizedBox(width: 4)],
  );
}

/// 一张分组纸片：细描边 + 极淡阴影，和画布拉开一点层次即可。
Widget featureCard(bool dark, List<Widget> children,
    {EdgeInsets? padding, EdgeInsets? margin}) {
  return Container(
    margin: margin ?? const EdgeInsets.only(bottom: 14),
    padding: padding ?? const EdgeInsets.fromLTRB(15, 15, 15, 12),
    decoration: surfaceBox(dark, shadowScale: 0.55),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    ),
  );
}

Widget featureLabel(bool dark, String text) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(text, style: sectionTitle(dark)),
    );

Widget featureHint(bool dark, String text, {Color? color}) => Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 4),
      child: Text(text,
          style: meta(dark, size: 11.5, color: color, height: 1.45)),
    );

/// 主行动按钮：满宽、跟随皮肤强调色、进行中显示进度圈。
Widget featurePrimary({
  required bool dark,
  required String label,
  required VoidCallback? onPressed,
  IconData? icon,
  bool busy = false,
}) {
  return SizedBox(
    width: double.infinity,
    height: 44,
    child: FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: C.brand,
        disabledBackgroundColor: fieldOf(dark),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(D.r)),
        elevation: 0,
      ),
      onPressed: busy ? null : onPressed,
      child: busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white))
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 17, color: Colors.white),
                  const SizedBox(width: 8),
                ],
                Text(label,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white)),
              ],
            ),
    ),
  );
}

/// 次级描边按钮。
Widget featureOutline({
  required bool dark,
  required String label,
  required VoidCallback? onPressed,
  IconData? icon,
}) {
  return SizedBox(
    height: 40,
    child: OutlinedButton(
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: borderOf(dark)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(D.r)),
      ),
      onPressed: onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: dark ? C.dInk2 : C.ink2),
            const SizedBox(width: 6),
          ],
          Text(label, style: ts(dark, size: 13)),
        ],
      ),
    ),
  );
}

/// 一行属性条：左侧名称、右侧数值，底部细进度。
Widget statBar(bool dark, String label, int value, Color color) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        SizedBox(width: 42, child: Text(label, style: sub(dark, size: 12))),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: (value.clamp(0, 100)) / 100,
              minHeight: 5,
              backgroundColor: fieldOf(dark),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ),
        const SizedBox(width: 9),
        SizedBox(
          width: 26,
          child: Text('$value',
              textAlign: TextAlign.right,
              style: numStyle(dark, size: 11.5)),
        ),
      ],
    ),
  );
}

/// 空态：一个淡图标 + 一句说明。
Widget featureEmpty(bool dark, IconData icon, String text) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Center(
        child: Column(
          children: [
            Icon(icon, size: 30, color: dark ? C.dInk3 : C.ink3),
            const SizedBox(height: 10),
            Text(text,
                textAlign: TextAlign.center,
                style: sub(dark, size: 12.5)),
          ],
        ),
      ),
    );

/// 统一的错误 / 提示条。
Widget featureNotice(bool dark, String text, {bool error = false}) {
  final c = error ? C.danger : accentOf(dark);
  return Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: c.withOpacity(0.08),
      borderRadius: BorderRadius.circular(D.r),
      border: Border.all(color: c.withOpacity(0.25), width: 0.8),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(error ? Icons.error_outline_rounded : Icons.info_outline_rounded,
            size: 16, color: c),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: meta(dark, size: 11.5, height: 1.45))),
      ],
    ),
  );
}
