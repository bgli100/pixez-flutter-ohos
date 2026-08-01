/*
 * Copyright (C) 2020. by perol_notsf, All rights reserved
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
 * this program. If not, see <http://www.gnu.org/licenses/>.
 *
 */
import 'package:flutter/material.dart';
import 'package:pixez/harmony_adapt/harmony_channel.dart';

/// 监听全局路由变化，自动控制 ArkTS HDS 底栏的显隐。
///
/// 显隐规则（任一成立即隐藏）：
/// - 路由栈深度 > 1（有页面/弹窗覆盖在主页之上）
/// - 非底栏布局（横屏侧栏 NavigationRail）
/// - 全屏模式（fullScreenStore）
class ShellBarsObserver extends NavigatorObserver {
  final Set<Route<dynamic>> _activeRoutes = {};
  bool _orientationHidden = false;
  bool _fullscreen = false;

  /// 全页覆盖隐藏：小说模式、登录页等自带导航的整页界面使用，
  /// 此时应隐藏原生 HDS 底栏，避免新旧导航栏同时出现。
  bool _forceHidden = false;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _activeRoutes.add(route);
    _sync();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _activeRoutes.remove(route);
    _sync();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _activeRoutes.remove(route);
    _sync();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (oldRoute != null) _activeRoutes.remove(oldRoute);
    if (newRoute != null) _activeRoutes.add(newRoute);
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

  void _sync() {
    HarmonyChannel.setShellBarsHidden(
      _forceHidden ||
          _activeRoutes.length > 1 ||
          _orientationHidden ||
          _fullscreen,
    );
  }
}
