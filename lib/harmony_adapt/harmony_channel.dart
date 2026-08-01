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
import 'dart:io';

import 'package:flutter/services.dart';

/// 鸿蒙原生通道（HDS 沉浸光感导航栏适配）。
///
/// 所有方法在非鸿蒙平台（Platform.isOhos 为 false）下均为空操作，
/// 不会对 Android / iOS / 桌面端造成任何影响。
abstract class HarmonyChannel {
  static final MethodChannel _channel = const MethodChannel('harmonyChannel')
    ..setMethodCallHandler(handler);

  /// 接收 ArkTS 侧推送的事件。
  /// 目前只有 HDS 底栏页签点击（原生底栏 → Flutter 切换页面）。
  static Future<dynamic> handler(MethodCall call) async {
    switch (call.method) {
      case 'showHome':
        _onShellTabSwitch?.call(0);
        break;
      case 'showRank':
        _onShellTabSwitch?.call(1);
        break;
      case 'showQuickView':
        _onShellTabSwitch?.call(2);
        break;
      case 'showSearch':
        _onShellTabSwitch?.call(3);
        break;
      case 'showMore':
        _onShellTabSwitch?.call(4);
        break;
      case 'miniBarTap':
        onMiniBarTap?.call();
        break;
      default:
        break;
    }
  }

  /// 原生 HDS 底栏页签切换回调：由主页面（AndroidHelloPage）注册
  static void Function(int index)? _onShellTabSwitch;

  static set onShellTabSwitch(void Function(int)? callback) =>
      _onShellTabSwitch = callback;

  /// 当前迷你胶囊点击回调：始终为顶层所有者的回调。
  /// 详情页可嵌套（点相关作品再推一层），顶层页面持有回调；
  /// 顶层弹出后自动恢复下一层（所有者栈）。
  static void Function()? get onMiniBarTap =>
      _miniBarOwners.isEmpty ? null : _miniBarOwners.last.callback;

  /// 主动向原生拉取设备信息（API 版本等），并缓存结果
  static Future<int?> getDeviceInfo() async {
    if (!Platform.isOhos) return null;
    for (int i = 0; i < 8; i++) {
      try {
        final Object? args = await _channel.invokeMethod<Object?>(
          'getDeviceInfo',
        );
        if (args is Map) {
          _sdkApiVersion = args['sdkApiVersion'] as int?;
          return _sdkApiVersion;
        }
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    return null;
  }

  /// 向原生发送 shell 配置（Flutter 侧计算后通知 ArkTS 是否启用原生 HDS 底栏）
  static Future<void> setShellBars({required bool useNativeTabs}) async {
    if (!Platform.isOhos) return;
    try {
      _channel.invokeMethod('setShellBars', {'useNativeTabs': useNativeTabs});
    } on PlatformException catch (_) {}
  }

  /// HDS 底栏当前是否为显示状态
  static bool _hiddenByPage = false;
  static bool get hdsBarVisible => !_hiddenByPage;

  /// 控制原生 HDS 底栏的即时显隐（弹窗、全屏、子页面等场景，无动画）
  static Future<void> setShellBarsHidden(
    bool hidden, {
    bool retry = false,
  }) async {
    if (!Platform.isOhos) return;
    _hiddenByPage = hidden;
    final int total = retry ? 8 : 1;
    for (int i = 0; i < total; i++) {
      try {
        _channel.invokeMethod('setShellBarsHidden', {'hidden': hidden});
        return;
      } catch (_) {
        if (i == total - 1) return;
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
    }
  }

  /// 同步主题色到 ArkTS HdsTabs 底栏
  static Future<void> setTabSelectedColor(String hexColor) async {
    if (!Platform.isOhos) return;
    try {
      _channel.invokeMethod('setTabSelectedColor', {'color': hexColor});
    } on PlatformException catch (_) {}
  }

  /// 同步 Flutter 页签切换到 ArkTS HdsTabs
  static Future<void> changeTabIndex(int index) async {
    if (!Platform.isOhos) return;
    try {
      _channel.invokeMethod('changeTabIndex', {'index': index});
    } on PlatformException catch (_) {}
  }

  /// 切换原生 HDS 底栏页签文案/图标：'main' 主界面 / 'novel' 小说模式
  static Future<void> setShellTabMode(String mode) async {
    if (!Platform.isOhos) return;
    try {
      _channel.invokeMethod('setShellTabMode', {'mode': mode});
    } on PlatformException catch (_) {}
  }

  /// 迷你胶囊所有者栈：详情页可嵌套（点相关作品再推一层 PictureListPage），
  /// 后注册的为顶层，决定胶囊的点击回调与内容；顶层弹出后自动恢复下一层。
  static final List<_MiniBarOwner> _miniBarOwners = [];

  /// 注册为迷你胶囊所有者（入栈；重复注册同一回调先移除再入栈）。
  /// 详情页/小说模式在 initState 时调用；[icon] 为 'favorite'（收藏钮）
  /// 或 'back'（小说模式返回钮），[active] 表示收藏激活态（实心心形/红色）。
  static void registerMiniBar(
    void Function() callback, {
    String icon = 'favorite',
    bool active = false,
  }) {
    if (!Platform.isOhos) return;
    unregisterMiniBar(callback);
    _miniBarOwners.add(_MiniBarOwner(callback, icon: icon, active: active));
    _pushMiniBarState();
  }

  /// 注销所有者（出栈）。仅当本回调仍为顶层时注销才改变当前胶囊内容，
  /// 否则仅从栈中移除，不影响仍在显示的上层页面。
  static void unregisterMiniBar(void Function() callback) {
    if (!Platform.isOhos) return;
    _miniBarOwners.removeWhere((o) => o.callback == callback);
    _pushMiniBarState();
  }

  /// 清空所有所有者并隐藏胶囊（主界面兜底，回到根页面时调用）
  static void resetMiniBar() {
    if (!Platform.isOhos) return;
    if (_miniBarOwners.isEmpty) return;
    _miniBarOwners.clear();
    _pushMiniBarState();
  }

  /// 本回调是否为当前顶层所有者：非顶层页面不得推送内容，
  /// 避免覆盖嵌套页面（上层详情页）的胶囊状态。
  static bool isMiniBarOwner(void Function() callback) =>
      _miniBarOwners.isNotEmpty && _miniBarOwners.last.callback == callback;

  /// 更新胶囊内容（图标/激活态），仅顶层所有者生效。
  /// 用于已在显示中的详情页在翻页/收藏后同步状态。
  static void updateMiniBar({String icon = 'favorite', bool active = false}) {
    if (!Platform.isOhos) return;
    if (_miniBarOwners.isEmpty) return;
    final top = _miniBarOwners.last;
    top.icon = icon;
    top.active = active;
    _pushMiniBarState();
  }

  static void _pushMiniBarState() {
    final bool show = _miniBarOwners.isNotEmpty;
    final top = _miniBarOwners.isEmpty ? null : _miniBarOwners.last;
    try {
      _channel.invokeMethod('setMiniBar', {
        'visible': show,
        'icon': show ? (top?.icon ?? 'favorite') : 'favorite',
        'active': show ? (top?.active ?? false) : false,
      });
    } on PlatformException catch (_) {}
  }

  /// 控制原生 HDS 底栏的滚动显隐（带动画）
  static Future<void> setShellBarsScrollHidden(bool hidden) async {
    if (!Platform.isOhos) return;
    try {
      _channel.invokeMethod('setShellBarsScrollHidden', {'hidden': hidden});
    } on PlatformException catch (_) {}
  }

  /// 缓存从 ArkTS 获取的 API 版本
  static int? _sdkApiVersion;

  /// 获取缓存的 API 版本（仅在 getDeviceInfo 调用后可用）
  static int? get sdkApiVersion => _sdkApiVersion;
}

/// 迷你胶囊所有者：保存点击回调与内容（图标/激活态）。
/// 由 HarmonyChannel 的所有者栈持有，栈顶为当前胶囊的拥有页面。
class _MiniBarOwner {
  final void Function() callback;
  String icon;
  bool active;

  _MiniBarOwner(this.callback, {this.icon = 'favorite', this.active = false});
}
