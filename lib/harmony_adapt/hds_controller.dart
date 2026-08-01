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
import 'package:flutter/foundation.dart';
import 'package:pixez/harmony_adapt/harmony_channel.dart';

/// 原生 HDS 悬浮底栏在 Flutter 侧需要预留的底部高度（vp）。
/// 用于在滚动内容末尾追加空白，让最后一项能滚动到悬浮底栏之上。
const double kHdsBarBottomPadding = 100.0;

/// 鸿蒙沉浸光感导航栏（HDS）控制器。
///
/// 集中管理 HDS 的生命周期与状态：
/// - 启动时查询 API 版本（>= 23 才支持 HDS 悬浮光感底栏），
///   结合用户设置（enableHdsBar）计算 useNativeTabs 并通知 ArkTS；
/// - 原生底栏页签点击 → 转发给主页面处理；
/// - Flutter 页签切换 → 同步回 ArkTS HdsTabs（原生发起的不回传，避免循环）；
/// - 主题色同步到 ArkTS HdsTabs 选中态。
///
/// 设置开关后需重启应用生效（useNativeTabs 在启动时一次性决定）。
class HdsController extends ChangeNotifier {
  bool _inited = false;
  bool _useNativeTabs = false;

  /// 当前是否使用原生 HDS 沉浸光感底栏（异步就绪，首帧可能为 false）
  bool get useNativeTabs => _useNativeTabs;

  int _selectedIndex = 0;
  int _primaryColorValue = 0;
  bool _fromNative = false;
  bool _disposed = false;

  /// 原生底栏页签切换回调，由主页面注册（与 Flutter 底栏点击走同一处理逻辑，
  /// 因此重复点击当前页签也能触发"回顶部"等行为）。
  void Function(int index)? onShellTabSwitch;

  /// 启动初始化：查询 API 版本，结合用户偏好计算 useNativeTabs，通知 ArkTS。
  /// 修改设置后需重启应用才会重新计算。
  Future<void> init({required bool enableHdsBar}) async {
    if (_inited) return;
    _inited = true;
    reconnectShellBridge();
    final apiVersion = await HarmonyChannel.getDeviceInfo();
    final useNative = apiVersion != null && apiVersion >= 23 && enableHdsBar;
    if (useNative == _useNativeTabs) return;
    _useNativeTabs = useNative;
    HarmonyChannel.setShellBars(useNativeTabs: useNative);
    if (_disposed) return;
    notifyListeners();
    // useNativeTabs 异步就绪后补发：主题色与当前页签，避免首帧状态缺失
    if (useNative) {
      if (_primaryColorValue != 0) {
        HarmonyChannel.setTabSelectedColor(_toHex(_primaryColorValue));
      }
      HarmonyChannel.changeTabIndex(_selectedIndex);
    }
  }

  /// 同步主题主色到 ArkTS HdsTabs（主页面 didChangeDependencies 时调用）。
  /// 缓存颜色值，供 init 异步就绪后补发。
  void syncThemeColor(int colorValue) {
    _primaryColorValue = colorValue;
    if (_useNativeTabs) {
      HarmonyChannel.setTabSelectedColor(_toHex(colorValue));
    }
  }

  /// Flutter 侧页签切换 → 同步到 ArkTS HdsTabs。
  /// 原生发起的切换（_fromNative）不回传，避免死循环。
  void syncTabIndex(int index) {
    _selectedIndex = index;
    if (_fromNative || !_useNativeTabs) return;
    HarmonyChannel.changeTabIndex(index);
  }

  /// 主页面 dispose 时解除其注册的页签回调。
  /// 路由替换（进入/退出小说模式）时，新页面 initState 先注册、旧页面
  /// dispose 后执行，因此仅当回调仍指向本页面时才清空，避免误伤新页面
  /// 刚注册的回调；原生→控制器桥由本控制器持有，不在页面级别清空。
  void unregisterPage(void Function(int index)? pageCallback) {
    if (onShellTabSwitch == pageCallback) {
      onShellTabSwitch = null;
    }
  }

  /// 重建原生底栏 → 本控制器的回调桥。
  /// 主页被替换（如进入小说模式）时，主页 dispose 会调用 unregisterPage()
  /// 清空 HarmonyChannel.onShellTabSwitch，需在此重新建立，
  /// 否则原生底栏页签点击无响应。
  void reconnectShellBridge() {
    HarmonyChannel.onShellTabSwitch = (int index) {
      // 原生发起的切换：同步置位，页面处理期间的回传会被跳过
      _fromNative = true;
      onShellTabSwitch?.call(index);
      _fromNative = false;
    };
  }

  static String _toHex(int value) =>
      '#${value.toRadixString(16).padLeft(8, '0').substring(2)}';

  @override
  void dispose() {
    _disposed = true;
    HarmonyChannel.onShellTabSwitch = null;
    super.dispose();
  }
}
