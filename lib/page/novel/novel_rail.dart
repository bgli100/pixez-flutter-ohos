/*
 * Copyright (C) 2020. by perol_notsf, All rights reserved
 *
 * This program is free software: you can redistribute it and/or modify it under
 * the terms of the GNU General Public License as published by the Free Software
 * Foundation, either version 3 of the License, or (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful, but WITHOUT ANY
 *  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 *  FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License along with
 *  this program. If not, see <http://www.gnu.org/licenses/>.
 */
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pixez/constants.dart';
import 'package:pixez/harmony_adapt/harmony_channel.dart';
import 'package:pixez/harmony_adapt/hds_controller.dart';
import 'package:pixez/i18n.dart';
import 'package:pixez/main.dart';
import 'package:pixez/page/hello/android_hello_page.dart';
import 'package:pixez/page/hello/hello_page.dart';
import 'package:pixez/page/hello/setting/setting_page.dart';
import 'package:pixez/page/novel/new/novel_new_page.dart';
import 'package:pixez/page/novel/rank/novel_rank_page.dart';
import 'package:pixez/page/novel/recom/novel_recom_page.dart';
import 'package:pixez/page/novel/search/novel_search_page.dart';

class NovelRail extends StatefulWidget {
  @override
  _NovelRailState createState() => _NovelRailState();
}

class _NovelRailState extends State<NovelRail> {
  int selectedIndex = 0;
  DateTime? _preTime;
  final _pageList = [
    NovelRecomPage(),
    NovelRankPage(),
    NovelNewPage(),
    NovelSearchPage(),
    SettingPage()
  ];
  late PageController _pageController;

  @override
  void initState() {
    _pageController = PageController();
    Constants.type = 1;
    fetcher.context = context;
    // 鸿蒙 HDS：小说模式同样使用原生沉浸光感底栏（开启时），
    // 原生底栏页签点击 → 切换小说页面；切换底栏页签文案/图标。
    // 注意先重建回调桥：主页被替换时 unregisterPage() 已清空原生→控制器桥。
    hdsController.onShellTabSwitch = _onTabSelected;
    hdsController.reconnectShellBridge();
    hdsController.syncTabIndex(selectedIndex);
    HarmonyChannel.setShellTabMode('novel');
    // 鸿蒙 HDS 迷你胶囊：小说模式返回钮（返回图片模式）
    if (hdsController.useNativeTabs) {
      HarmonyChannel.registerMiniBar(_onMiniBarTap, icon: 'back');
    }
    super.initState();
  }

  @override
  void dispose() {
    // 解除小说模式页签回调（仅当回调仍指向本页面时才清空，避免误伤
    // 路由替换后新页面已注册的回调），并恢复主界面底栏页签文案/图标
    HarmonyChannel.setShellTabMode('main');
    HarmonyChannel.unregisterMiniBar(_onMiniBarTap);
    hdsController.unregisterPage(_onTabSelected);
    _pageController.dispose();
    super.dispose();
  }

  /// 迷你胶囊点击：返回图片模式（清空整个小说栈，确保 NovelRail 被销毁、胶囊隐藏）
  void _onMiniBarTap() {
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
        MaterialPageRoute(
            builder: (context) => Platform.isIOS || Platform.isMacOS
                ? HelloPage()
                : AndroidHelloPage()),
        (route) => false);
  }

  /// 页签切换统一处理：Flutter 底栏与原生 HDS 底栏共用。
  /// 重复点击当前页签触发"回顶部"（topStore）。
  void _onTabSelected(int index) {
    if (selectedIndex == index) {
      topStore.setTop("${index + 1}00");
    }
    setState(() {
      selectedIndex = index;
    });
    if (_pageController.hasClients) _pageController.jumpToPage(index);
    hdsController.syncTabIndex(index);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth > constraints.maxHeight;
        // 鸿蒙 HDS：横屏（侧栏布局）时隐藏原生底栏
        if (hdsController.useNativeTabs) {
          shellBarsObserver.onOrientationChanged(!wide);
        }
        // 鸿蒙 HDS 开启且竖屏时，用原生沉浸光感底栏替代 Flutter 导航栏
        final useNative = hdsController.useNativeTabs && !wide;
        return PopScope(
          onPopInvokedWithResult: (didPop, result) async {
            userSetting.setAnimContainer(!userSetting.animContainer);
            if (didPop) return;
            if (!userSetting.isReturnAgainToExit) {
              return;
            }
            if (_preTime == null ||
                DateTime.now().difference(_preTime!) > Duration(seconds: 2)) {
              setState(() {
                _preTime = DateTime.now();
              });
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                duration: Duration(seconds: 1),
                content: Text(I18n.of(context).return_again_to_exit),
              ));
            }
          },
          canPop: !userSetting.isReturnAgainToExit ||
              _preTime != null &&
                  DateTime.now().difference(_preTime!) <= Duration(seconds: 2),
          child: Scaffold(
            // 鸿蒙 HDS：迷你返回栏激活时隐藏 Flutter 返回钮（新旧不共存）
            floatingActionButton: useNative
                ? null
                : FloatingActionButton(
                    onPressed: () {
                      Navigator.of(context, rootNavigator: true)
                          .pushAndRemoveUntil(
                              MaterialPageRoute(
                                  builder: (context) => Platform.isIOS ||
                                          Platform.isMacOS
                                      ? HelloPage()
                                      : AndroidHelloPage()),
                              (route) => false);
                    },
                    child: Icon(Icons.picture_in_picture),
                  ),
            bottomNavigationBar:
                useNative ? null : _buildNavigationBar(context),
            body: PageView.builder(
              itemCount: _pageList.length,
              controller: _pageController,
              onPageChanged: (index) {
                setState(() {
                  selectedIndex = index;
                });
                hdsController.syncTabIndex(index);
              },
              itemBuilder: (context, index) {
                return _pageList[index];
              },
            ),
          ),
        );
      },
    );
  }

  NavigationBar _buildNavigationBar(BuildContext context) {
    return NavigationBar(
      destinations: [
        NavigationDestination(
            icon: Icon(Icons.home), label: I18n.of(context).home),
        NavigationDestination(
            icon: Icon(
              Icons.leaderboard,
            ),
            label: I18n.of(context).rank),
        NavigationDestination(
            icon: Icon(Icons.favorite), label: I18n.of(context).news),
        NavigationDestination(
            icon: Icon(Icons.search), label: I18n.of(context).search),
        NavigationDestination(
            icon: Icon(Icons.settings), label: I18n.of(context).setting)
      ],
      selectedIndex: selectedIndex,
      onDestinationSelected: _onTabSelected,
    );
  }
}
