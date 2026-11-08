import 'package:flutter/material.dart';

import '../services/model_brand.dart';
import '../theme.dart';

/// 模型列表里的官方品牌图标。
///
/// 一律用内置的 256px 彩色 PNG（见 `tool/build_brand_icons.py`），
/// 统一放在近白色圆角方块里：黑色系官方 logo 在深浅主题下都看得清，
/// 彩色 logo 也不会被背景吃掉，整列风格完全一致。
class BrandIcon extends StatelessWidget {
  final ModelBrand brand;
  final double size;
  final bool dark;

  const BrandIcon({
    super.key,
    required this.brand,
    required this.dark,
    this.size = 38,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: dark ? const Color(0xFFF1F2F5) : Colors.white,
        borderRadius: BorderRadius.circular(size * 0.27),
        border: Border.all(
          color: dark ? const Color(0xFF3A3A40) : C.line,
          width: 0.8,
        ),
      ),
      padding: EdgeInsets.all(size * 0.17),
      child: Image.asset(
        brand.asset,
        filterQuality: FilterQuality.high,
        errorBuilder: (_, __, ___) => Icon(
          Icons.smart_toy_outlined,
          size: size * 0.48,
          color: dark ? C.dInk2 : C.ink2,
        ),
      ),
    );
  }
}

/// 通用模型行：**官方图标 + 大字模型名 + 小字供应商**。
///
/// 弹层、设置页、搜索结果三处共用同一个组件，避免三种长得不一样的列表。
/// 只有选中态会多一个对勾，不再堆「视觉 / 推理 / 选用 / 切换连接」一串标签。
class BrandModelTile extends StatelessWidget {
  final String modelId;
  final String subtitle;
  final bool selected;
  final bool dark;
  final VoidCallback onTap;
  final double iconSize;

  /// 可选的能力后缀，会并在副标题末尾（如「· 视觉」），不另起标签。
  final String? capability;

  /// v4.13：单行紧凑版——只留「图标 + 模型名」，行更高、字号更大、
  /// 没有分隔线也没有选中底色，用在对「简洁」要求最高的换模型弹层里。
  final bool compact;

  const BrandModelTile({
    super.key,
    required this.modelId,
    required this.subtitle,
    required this.selected,
    required this.dark,
    required this.onTap,
    this.iconSize = 38,
    this.capability,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final accent = accentOf(dark);
    final brand = resolveModelBrand(modelId);
    if (compact) return _compactTile(accent, brand);
    final sub = capability == null || capability!.isEmpty
        ? subtitle
        : (subtitle.isEmpty ? capability! : '$subtitle · $capability');
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 58),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? accent.withOpacity(dark ? 0.12 : 0.06) : null,
          border: Border(bottom: BorderSide(color: hairOf(dark), width: 1)),
        ),
        child: Row(
          children: [
            BrandIcon(brand: brand, size: iconSize, dark: dark),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    modelId,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ts(dark,
                        size: 13.5,
                        weight: selected ? FontWeight.w700 : FontWeight.w600),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    sub.isEmpty ? brand.label : sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: meta(dark, size: 11.5),
                  ),
                ],
              ),
            ),
            if (selected) ...[
              const SizedBox(width: 8),
              Icon(Icons.check_circle_rounded, size: 18, color: accent),
            ],
          ],
        ),
      ),
    );
  }

  /// 单行：图标 + 15px 模型名 + 选中对勾，四周留白，无分隔线。
  Widget _compactTile(Color accent, ModelBrand brand) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
        child: Row(
          children: [
            BrandIcon(brand: brand, size: iconSize, dark: dark),
            const SizedBox(width: 13),
            Expanded(
              child: Text(
                modelId,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.25,
                  letterSpacing: -0.1,
                  fontWeight:
                      selected ? FontWeight.w600 : FontWeight.w500,
                  color: dark ? C.dInk : C.ink,
                ),
              ),
            ),
            if (selected) ...[
              const SizedBox(width: 10),
              Icon(Icons.check_rounded, size: 20, color: accent),
            ],
          ],
        ),
      ),
    );
  }
}
