/*
 * Copyright (C) 2020. by perol_notsf, All rights reserved.
 *
 * This program is free software: you can redistribute it and/or modify it under
 * the terms of the GNU General Public License as published by the Free Software
 * Foundation, either version 3 of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT ANY
 * WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along with
 * this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 */

import 'dart:math';

import 'package:material_ui/material_ui.dart';

/// 鸿蒙全设备形态适配的窗口断点（单位 vp，即 Flutter 逻辑像素）。
///
/// 鸿蒙各形态的实际宽度（px / (dpi/160)）：
/// - 手机 Pura X View 1320px@480dpi ≈ 440vp（compact）
/// - 折叠屏 Mate X6 展开 2240px@500dpi ≈ 717vp（medium）
/// - 三折叠 Mate XT 展开 3184px@460dpi ≈ 1108vp（expanded）
/// - 平板 MatePad Pro 11 2560px@360dpi ≈ 1138vp（expanded）
/// - 2in1 MateBook Pro 3120px@304dpi ≈ 1642vp（expanded）
///
/// 与 Material 3 的 compact / medium / expanded 三档一致。
const double kCompactWidthBreakpoint = 600;
const double kExpandedWidthBreakpoint = 840;

/// 瀑布流卡片的最小可读宽度（vp）。宽屏下据此增加列数，避免两列巨图。
const double kMinCardWidth = 220;

/// 是否用侧边导航栏（NavigationRail）替代底部导航栏。
///
/// - 平板 / 2in1 / 折叠屏展开（宽度 >= 840vp）一律用侧栏；
/// - 手机、折叠屏半开等窄屏只有在"宽 > 高"（横屏）时才用侧栏，
///   与上游 Android 版行为一致。
bool isWideNavigationLayout(double width, double height) {
  if (width >= kExpandedWidthBreakpoint) return true;
  return width > height && width >= kCompactWidthBreakpoint;
}

/// 宽屏下按最小卡片宽度补足瀑布流列数。
///
/// 保留用户在设置里指定的列数（不减少），只有在窗口足够宽、当前列数会让
/// 卡片被拉伸得过大时才增加列数；最多 10 列。手机宽度下原样返回，不改变
/// 上游 Android/iOS 的表现。
int adaptCrossCount(BuildContext context, int count) {
  final width = MediaQuery.sizeOf(context).width;
  if (width < kCompactWidthBreakpoint) return count;
  final fit = (width / kMinCardWidth).floor();
  if (fit <= count) return count;
  return min(fit, 10);
}
