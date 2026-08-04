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
import 'package:pixez/harmony_adapt/hds_controller.dart';
import 'package:pixez/main.dart';

/// 鸿蒙 HDS 迷你胶囊作用域：包裹任意页面，自动把该页面注册为原生胶囊的所有者。
///
/// - 页面成为顶层时显示胶囊（[icon]），点击触发 [onTap]（与原 Flutter 悬浮按钮同逻辑）；
/// - 被上层页面覆盖时隐藏（didPushNext），返回时恢复（didPopNext），销毁时注销；
/// - useNativeTabs 异步就绪后自动补注册。
///
/// 用于把各类 Flutter 悬浮按钮（FAB）替换为原生沉浸胶囊，避免新旧按钮共存。
/// 非鸿蒙平台（useNativeTabs 为 false）下不注册，不影响其他平台。
class HdsMiniBarScope extends StatefulWidget {
  /// 胶囊图标名（对应 ArkTS 侧 miniIcon() 的映射键）：
  /// 'refresh' / 'close' / 'delete' / 'photo' / 'fullscreen' 等
  final String icon;

  /// 胶囊点击回调（与原 Flutter 悬浮按钮的 onPressed 相同逻辑）
  final VoidCallback onTap;

  final Widget child;

  const HdsMiniBarScope({
    super.key,
    required this.icon,
    required this.onTap,
    required this.child,
  });

  @override
  State<HdsMiniBarScope> createState() => _HdsMiniBarScopeState();
}

class _HdsMiniBarScopeState extends State<HdsMiniBarScope> with RouteAware {
  bool _registered = false;

  @override
  void initState() {
    super.initState();
    if (hdsController.useNativeTabs) {
      _register();
    } else {
      // useNativeTabs 异步就绪后补注册
      hdsController.addListener(_onHdsChanged);
    }
    routeObserver.subscribe(this, ModalRoute.of(context)!);
  }

  void _onHdsChanged() {
    if (mounted && hdsController.useNativeTabs) {
      _register();
    }
  }

  void _register() {
    if (_registered || !hdsController.useNativeTabs) return;
    _registered = true;
    HarmonyChannel.registerMiniBar(_handleTap, icon: widget.icon);
  }

  void _unregister() {
    if (!_registered) return;
    _registered = false;
    HarmonyChannel.unregisterMiniBar(_handleTap);
  }

  /// 稳定回调身份：始终指向本 State 的实例方法，
  /// 即使父级重建产生新的 [HdsMiniBarScope.onTap] 闭包也不影响注册/注销匹配。
  void _handleTap() => widget.onTap();

  @override
  void didPushNext() => _unregister();

  @override
  void didPopNext() => _register();

  /// 本页开始退出时立即注销胶囊：dispose 要等返回过渡动画结束才执行，
  /// 若只靠 dispose 注销，过渡期间（约 300ms）胶囊会暂留闪现。
  @override
  void didPop() => _unregister();

  /// 本页被移除（pushAndRemoveUntil 等）时同样立即注销
  @override
  void didRemove() => _unregister();

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    hdsController.removeListener(_onHdsChanged);
    _unregister();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
