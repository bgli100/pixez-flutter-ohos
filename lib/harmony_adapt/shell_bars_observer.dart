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
import 'package:flutter/material.dart';
import 'package:pixez/harmony_adapt/harmony_channel.dart';

/// 监听全局路由变化，自动控制 ArkTS HDS 底栏的显隐。
///
/// 显隐规则（任一成立即隐藏）：
/// - 主界面之上还有页面（路由栈深 > 0，含弹窗/对话框）
/// - 非底栏布局（横屏/平板侧栏 NavigationRail）
/// - 全屏模式（fullScreenStore）
class ShellBarsObserver extends NavigatorObserver {
  bool _orientationHidden = false;
  bool _fullscreen = false;

  /// 全页覆盖隐藏：小说模式、登录页等自带导航的整页界面使用，
  /// 此时应隐藏原生 HDS 底栏，避免新旧导航栏同时出现。
  bool _forceHidden = false;

  /// 主界面之上的路由层数（0 = 停在主界面）。
  ///
  /// 用计数而不是 `Set<Route>`：路由被 `pushAndRemoveUntil` 批量移除、
  /// 或页面在过渡动画中被替换时，Set 容易残留未收到回调的 Route，
  /// 一旦残留就再也不会变回 0 → 底栏永久隐藏（"登录后没有底栏"）。
  /// 计数只依赖 push/pop/remove 三个配对事件，且 everywhere clamp 到 0。
  int _routeDepth = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    // 第一个路由（home）不计入层数
    if (previousRoute != null) _routeDepth++;
    _sync();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_routeDepth > 0) _routeDepth--;
    _sync();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute == null) {
      _routeDepth = 0;
    } else if (_routeDepth > 0) {
      _routeDepth--;
    }
    _sync();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    // 替换不改变栈深
    _sync();
  }

  /// 由主页面调用：非竖屏底栏布局（横屏侧栏）时隐藏底栏。
  /// 子页面覆盖期间也照常记录，避免返回主页后用的是过期方向。
  void onOrientationChanged(bool useBottomNav) {
    _orientationHidden = !useBottomNav;
    _sync();
  }

  /// 全屏模式（隐藏 Flutter 底栏的同时隐藏原生 HDS 底栏）
  void setFullscreen(bool value) {
    _fullscreen = value;
    _sync();
  }

  /// 整页覆盖（小说模式、登录页等自带导航的界面）时强制隐藏原生 HDS 底栏
  void setForceHidden(bool value) {
    _forceHidden = value;
    _sync();
  }

  /// useNativeTabs 状态变化（原生底栏启用/停用）、隐藏锁释放后重新同步一次
  /// 显隐。启动早期 hdsController.init 异步就绪时，隐藏指令可能早于底栏创建
  /// 而丢失，就绪后按当前状态重新计算并补发。
  void resync() {
    _sync();
  }

  void _sync() {
    HarmonyChannel.setShellBarsHidden(
      _forceHidden || _routeDepth > 0 || _orientationHidden || _fullscreen,
    );
  }
}
