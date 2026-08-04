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
import 'dart:async';
import 'dart:io';

import 'package:bot_toast/bot_toast.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:pixez/constants.dart';
import 'package:pixez/er/fetcher.dart';
import 'package:pixez/er/hoster.dart';
import 'package:pixez/harmony_adapt/hds_controller.dart';
import 'package:pixez/harmony_adapt/shell_bars_observer.dart';
import 'package:pixez/network/onezero_client.dart';
import 'package:pixez/er/illust_cacher.dart';
import 'package:pixez/i18n.dart';
import 'package:pixez/page/novel/history/novel_history_store.dart';
import 'package:pixez/page/splash/splash_page.dart';
import 'package:pixez/page/splash/splash_store.dart';
import 'package:pixez/paths_plugin.dart';
import 'package:pixez/single_instance_plugin.dart';
import 'package:pixez/src/generated/i18n/app_localizations.dart';
import 'package:pixez/store/account_store.dart';
import 'package:pixez/store/book_tag_store.dart';
import 'package:pixez/store/fullscreen_store.dart';
import 'package:pixez/store/mute_store.dart';
import 'package:pixez/store/save_store.dart';
import 'package:pixez/store/tag_history_store.dart';
import 'package:pixez/store/top_store.dart';
import 'package:pixez/store/user_setting.dart';
import 'package:rhttp/rhttp.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final RouteObserver<ModalRoute<void>> routeObserver =
    RouteObserver<ModalRoute<void>>();
final UserSetting userSetting = UserSetting();
final SaveStore saveStore = SaveStore();
final MuteStore muteStore = MuteStore();
final AccountStore accountStore = AccountStore();
final TagHistoryStore tagHistoryStore = TagHistoryStore();
final NovelHistoryStore novelHistoryStore = NovelHistoryStore();
final TopStore topStore = TopStore();
final BookTagStore bookTagStore = BookTagStore();
final SplashStore splashStore = SplashStore();
final Fetcher fetcher = new Fetcher();
final FullScreenStore fullScreenStore = FullScreenStore();

/// 鸿蒙 HDS 沉浸光感导航栏：全局路由显隐观察者
final ShellBarsObserver shellBarsObserver = ShellBarsObserver();

/// 鸿蒙 HDS 沉浸光感导航栏：状态控制器
final HdsController hdsController = HdsController();

/// 鸿蒙 HDS：内容末尾应追加的空白高度（vp）。
/// 开启 HDS 时返回底栏高度，否则为 0。把该高度追加到滚动内容末尾的空白项，
/// 使内容可滚动到悬浮底栏之后（沉浸式），且最后一项能拖到底栏之上。
double hdsBottomSpace() =>
    hdsController.useNativeTabs ? kHdsBarBottomPadding : 0.0;

main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await Rhttp.init();
  await MmapCache.init();

  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final dbPath = await Paths.getDatabaseFolderPath();
    if (dbPath != null) databaseFactory.setDatabasesPath(dbPath);
    SingleInstancePlugin.initialize();
  }

  runApp(ProviderScope(child: MyApp(arguments: args)));
}

class MyApp extends StatefulWidget {
  final List<String> arguments;

  const MyApp({super.key, required this.arguments});
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  AppLifecycleState? _appState;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (Platform.isIOS) {
      setState(() {
        _appState = state;
      });
    }
  }

  @override
  void dispose() {
    saveStore.dispose();
    topStore.dispose();
    fetcher.stop();
    subscription.cancel();
    if (Platform.isIOS) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  late StreamSubscription<String> subscription;

  @override
  void initState() {
    subscription = topStore.topStream.listen((event) {
      if (event == "main") {
        setState(() {});
      }
    });
    userSetting.askInit();
    userSetting.init();
    accountStore.fetch();
    bookTagStore.init();
    muteStore.init();

    super.initState();
    if (Platform.isIOS) WidgetsBinding.instance.addObserver(this);
    Future.delayed(Duration.zero, () {
      SingleInstancePlugin.argsParser(widget.arguments);
    });
  }

  @override
  Widget build(BuildContext context) {
    return _buildMaterial(context);
  }

  Widget _buildMaterial(BuildContext context) {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarContrastEnforced: false,
        statusBarColor: Colors.transparent,
      ),
    );
    final botToastBuilder = BotToastInit();
    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        return Observer(
          builder: (context) {
            ColorScheme lightColorScheme;
            ColorScheme darkColorScheme;
            if (userSetting.useDynamicColor &&
                lightDynamic != null &&
                darkDynamic != null) {
              lightColorScheme = lightDynamic.harmonized();
              darkColorScheme = darkDynamic.harmonized();
            } else {
              Color primary = userSetting.seedColor;
              lightColorScheme = ColorScheme.fromSeed(seedColor: primary);
              darkColorScheme = ColorScheme.fromSeed(
                seedColor: primary,
                brightness: Brightness.dark,
              );
            }
            final brightness =
                SchedulerBinding.instance.platformDispatcher.platformBrightness;
            if (userSetting.themeInitState != 1) {
              return Container(
                color: brightness == Brightness.dark
                    ? Colors.black
                    : Colors.white,
                child: Center(
                  child: Material(child: CircularProgressIndicator()),
                ),
              );
            }
            return MaterialApp(
              navigatorObservers: [
                BotToastNavigatorObserver(),
                routeObserver,
                shellBarsObserver,
              ],
              locale: userSetting.locale,
              home: Builder(
                builder: (context) {
                  return AnnotatedRegion<SystemUiOverlayStyle>(
                    value: SystemUiOverlayStyle(
                      systemNavigationBarColor: Colors.transparent,
                      systemNavigationBarDividerColor: Colors.transparent,
                      systemNavigationBarContrastEnforced: false,
                      statusBarColor: Colors.transparent,
                    ),
                    child: SplashPage(),
                  );
                },
              ),
              title: 'PixEz',
              builder: (context, child) {
                if (Platform.isIOS) child = _buildMaskBuilder(context, child);
                child = botToastBuilder(context, child);
                I18n.context = context;
                return child;
              },
              themeMode: userSetting.themeMode,
              theme: ThemeData(
                brightness: Brightness.light,
                useMaterial3: true,
                fontFamily: userSetting.useBundledFont
                    ? 'HarmonyOS_Sans'
                    : null,
                primaryColor: lightColorScheme.primary,
                colorScheme: lightColorScheme,
                scaffoldBackgroundColor: lightColorScheme.surface,
                cardColor: lightColorScheme.surfaceContainer,
                chipTheme: ChipThemeData(
                  backgroundColor: lightColorScheme.surface,
                ),
                canvasColor: lightColorScheme.surfaceContainer,
                dialogTheme: DialogThemeData(
                  backgroundColor: lightColorScheme.surfaceContainer,
                ),
                pageTransitionsTheme: PageTransitionsTheme(
                  builders: {
                    TargetPlatform.android: ZoomPageTransitionsBuilder(),
                    TargetPlatform.ohos: ZoomPageTransitionsBuilder(),
                    TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
                  },
                ),
              ),
              darkTheme: ThemeData(
                brightness: Brightness.dark,
                useMaterial3: true,
                fontFamily: userSetting.useBundledFont
                    ? 'HarmonyOS_Sans'
                    : null,
                scaffoldBackgroundColor: userSetting.isAMOLED
                    ? Colors.black
                    : null,
                pageTransitionsTheme: PageTransitionsTheme(
                  builders: {
                    TargetPlatform.android: ZoomPageTransitionsBuilder(),
                    TargetPlatform.ohos: ZoomPageTransitionsBuilder(),
                    TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
                  },
                ),
                // tabBarTheme: TabBarTheme(dividerColor: Colors.transparent),
                tabBarTheme: TabBarThemeData(dividerColor: Colors.transparent),
                colorScheme: darkColorScheme,
              ),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
            );
          },
        );
      },
    );
  }

  Widget? _buildMaskBuilder(BuildContext context, Widget? widget) {
    if (!userSetting.nsfwMask) return widget;
    final needShowMask = _appState == AppLifecycleState.inactive;
    return Stack(
      children: [
        widget ?? const SizedBox.shrink(),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 500),
          child: needShowMask
              ? Container(
                  key: const ValueKey('recent_screen_mask'),
                  color: Theme.of(context).canvasColor,
                  child: const Center(child: Icon(Icons.privacy_tip_outlined)),
                )
              : const SizedBox.shrink(key: ValueKey('recent_screen_unmask')),
        ),
      ],
    );
  }
}
