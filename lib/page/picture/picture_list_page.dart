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

import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:mobx/mobx.dart';
import 'package:pixez/harmony_adapt/harmony_channel.dart';
import 'package:pixez/lighting/lighting_store.dart';
import 'package:pixez/main.dart';
import 'package:pixez/page/picture/illust_favorite_action.dart';
import 'package:pixez/page/picture/illust_lighting_page.dart';
import 'package:pixez/page/picture/illust_store.dart';

class PictureListPage extends StatefulWidget {
  final IllustStore store;
  final List<IllustStore> iStores;
  final String? heroString;
  final LightingStore? lightingStore;

  const PictureListPage({
    Key? key,
    required this.lightingStore,
    required this.store,
    required this.iStores,
    this.heroString,
  }) : super(key: key);

  @override
  _PictureListPageState createState() => _PictureListPageState();
}

class _PictureListPageState extends State<PictureListPage> with RouteAware {
  late PageController _pageController;
  late int nowPosition;
  late LightingStore? _lightingStore;
  late List<IllustStore> _iStores;
  late IllustStore _store;
  double screenWidth = 0;

  /// 迷你胶囊是否已显示（去重，防止 onPageChanged 反复 +1 引用计数）
  bool _miniBarShown = false;

  /// 是否正在退出（返回开始即隐藏胶囊，避免返回过渡中胶囊上移闪烁）
  bool _popping = false;

  /// 当前插画收藏状态监听：收藏状态变化时同步迷你栏图标（实心/空心）
  ReactionDisposer? _stateReaction;

  @override
  void initState() {
    _store = widget.store;
    _iStores = widget.iStores;
    _lightingStore = widget.lightingStore;
    nowPosition = _iStores.indexOf(_store);
    _pageController = PageController(initialPage: nowPosition);
    super.initState();
    // 鸿蒙 HDS 迷你胶囊：详情页收藏钮（由当前页状态驱动）。
    // 注册为胶囊所有者（入栈为顶层）；useNativeTabs 异步就绪（启动初期可能
    // 为 false），由 _syncMiniBar 内部检查，未就绪时不会真正显示胶囊。
    // 订阅路由可见性：嵌套详情页弹出返回时（didPopNext）重新注册为顶层，
    // 恢复本页收藏状态与点击回调。
    routeObserver.subscribe(this, ModalRoute.of(context)!);
    hdsController.addListener(_onHdsChanged);
    _syncMiniBar();
    _bindStateReaction();
  }

  /// useNativeTabs 异步就绪后回调：补发胶囊显示，无需等待翻页触发
  void _onHdsChanged() {
    if (mounted && hdsController.useNativeTabs) {
      _syncMiniBar();
    }
  }

  /// 嵌套详情页弹出、本页重新可见（didPopNext）：重新注册为胶囊顶层
  /// 所有者，恢复本页收藏状态与点击回调（否则胶囊仍绑定被弹出页）。
  @override
  void didPopNext() {
    if (!mounted || !hdsController.useNativeTabs) return;
    _miniBarShown = false; // 强制走注册分支，重新入栈为顶层
    _syncMiniBar();
  }

  /// 上层页面（大图页、评论、用户页等）覆盖本页时隐藏迷你胶囊，
  /// 避免遮挡上层内容（与非 HDS 模式一致：收藏钮只在详情页自身显示）。
  @override
  void didPushNext() {
    if (!mounted || !hdsController.useNativeTabs || !_miniBarShown) return;
    _miniBarShown = false;
    HarmonyChannel.unregisterMiniBar(_onMiniBarTap);
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    hdsController.removeListener(_onHdsChanged);
    _stateReaction?.call();
    if (_miniBarShown) {
      _miniBarShown = false;
      HarmonyChannel.unregisterMiniBar(_onMiniBarTap);
    }
    _pageController.dispose();
    super.dispose();
  }

  /// 当前展示的插画下标（最后一个「下一页」占位页也归到最后一幅）
  int get _currentIndex =>
      nowPosition < _iStores.length ? nowPosition : _iStores.length - 1;

  /// 监听当前插画的收藏状态，变化时同步迷你栏图标（含异步加载完成后的首次同步）
  void _bindStateReaction() {
    _stateReaction?.call();
    final store = _iStores[_currentIndex];
    _stateReaction = reaction((_) => store.state, (_) => _syncMiniBar());
  }

  /// 将当前收藏状态同步到原生迷你胶囊（激活态：已收藏）
  void _syncMiniBar() {
    if (_popping || !mounted || !hdsController.useNativeTabs) return;
    final store = _iStores[_currentIndex];
    if (!_miniBarShown) {
      _miniBarShown = true;
      HarmonyChannel.registerMiniBar(
        _onMiniBarTap,
        icon: 'favorite',
        active: store.state != 0,
      );
    } else {
      // 非顶层页面（被嵌套详情页覆盖）不推送内容，避免覆盖上层页面的状态
      if (!HarmonyChannel.isMiniBarOwner(_onMiniBarTap)) return;
      HarmonyChannel.updateMiniBar(icon: 'favorite', active: store.state != 0);
    }
  }

  /// 迷你胶囊点击：与收藏悬浮钮同逻辑（含保存/标签/关注选项）
  Future<void> _onMiniBarTap() async {
    final store = _iStores[_currentIndex];
    if (store.illusts == null) {
      // 插画尚未加载完成：先拉取，避免 star() 对 null illusts 抛错
      await store.fetch();
      if (!mounted || store.illusts == null) return;
    }
    await toggleIllustFavorite(context, store);
    // 收藏请求期间页面可能已退出，避免退出后重新显示胶囊
    if (!mounted) return;
    _syncMiniBar();
  }

  @override
  Widget build(BuildContext context) {
    screenWidth = MediaQuery.of(context).size.width / 2;
    return PopScope(
      onPopInvokedWithResult: (didPop, result) {
        // 详情页开始退出时立即注销胶囊所有者：
        // 否则返回过渡期间 shellBarsHidden 翻转会让胶囊先上移避让底栏再消失（闪烁）
        if (didPop && _miniBarShown && hdsController.useNativeTabs) {
          _popping = true;
          _miniBarShown = false;
          HarmonyChannel.unregisterMiniBar(_onMiniBarTap);
        }
      },
      child: Observer(
        builder: (_) {
          return MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(gestureSettings: DeviceGestureSettings(touchSlop: 50)),
            child: ScrollConfiguration(
              // Flutter excludes mouse from dragDevices by default (#1308).
              behavior: ScrollConfiguration.of(context).copyWith(
                dragDevices: {
                  PointerDeviceKind.touch,
                  PointerDeviceKind.stylus,
                  PointerDeviceKind.invertedStylus,
                  PointerDeviceKind.trackpad,
                  PointerDeviceKind.mouse,
                },
              ),
              child: PageView.builder(
                controller: _pageController,
                physics: userSetting.swipeChangeArtwork
                    ? null
                    : NeverScrollableScrollPhysics(),
                onPageChanged: (index) {
                  nowPosition = index;
                  _syncMiniBar();
                  _bindStateReaction();
                },
                itemBuilder: (BuildContext context, int index) {
                  if (index == _iStores.length && _lightingStore != null) {
                    return PictureListNextPage(lightingStore: _lightingStore!);
                  }
                  final f = _iStores[index];
                  String? tag = nowPosition == index ? widget.heroString : null;
                  return MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      gestureSettings: DeviceGestureSettings(
                        touchSlop: kTouchSlop,
                      ),
                    ),
                    child: IllustLightingPage(
                      id: f.id,
                      heroString: tag,
                      store: f,
                      onHorizontalDragEnd: (details) {
                        _onDrag(details);
                      },
                    ),
                  );
                },
                itemCount: _iStores.length + 1,
              ),
            ),
          );
        },
      ),
    );
  }

  _onDrag(DragEndDetails details) {
    final pixelsPerSecond = details.velocity.pixelsPerSecond;
    if (pixelsPerSecond.dy.abs() > pixelsPerSecond.dx.abs()) return;
    if (pixelsPerSecond.dx.abs() > screenWidth) {
      int result = nowPosition;
      if (pixelsPerSecond.dx < 0)
        result++;
      else
        result--;
      _pageController.animateToPage(
        result,
        duration: Duration(milliseconds: 200),
        curve: Curves.easeInOut,
      );
      if (result >= _iStores.length) result = _iStores.length - 1;
      if (result < 0) result = 0;
      setState(() {
        nowPosition = result;
      });
    }
  }
}

class PictureListNextPage extends StatefulWidget {
  final LightingStore lightingStore;
  const PictureListNextPage({super.key, required this.lightingStore});

  @override
  State<PictureListNextPage> createState() => _PictureListNextPageState();
}

class _PictureListNextPageState extends State<PictureListNextPage> {
  late LightingStore _lightingStore;
  bool? loadResult;
  @override
  void initState() {
    _lightingStore = widget.lightingStore;
    super.initState();
    _maybeFetch(true);
  }

  _maybeFetch(bool firstIn) async {
    if (_lightingStore.nextUrl == null) return;
    try {
      if (!firstIn) {
        setState(() {
          loadResult = null;
        });
      }
      final result = await _lightingStore.fetchNext();
      if (mounted) {
        setState(() {
          loadResult = result;
        });
      }
    } catch (e) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_lightingStore.nextUrl == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: Text("No More")),
      );
    }
    if (loadResult == false) {
      return Scaffold(
        appBar: AppBar(),
        body: Container(
          child: Center(
            child: Column(
              children: [
                Text("Load Failed"),
                TextButton(
                  onPressed: () {
                    _maybeFetch(false);
                  },
                  child: Text("Retry"),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
