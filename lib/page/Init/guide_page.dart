import 'dart:io';

import 'package:animations/animations.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pixez/er/leader.dart';
import 'package:pixez/er/prefer.dart';
import 'package:pixez/harmony_adapt/harmony_channel.dart';
import 'package:pixez/main.dart';
import 'package:pixez/network/api_client.dart';
import 'package:pixez/page/Init/init_page.dart';
import 'package:pixez/page/about/languages.dart';
import 'package:pixez/page/network/network_page.dart';

class GuidePage extends StatefulWidget {
  @override
  _GuidePageState createState() => _GuidePageState();
}

class _GuidePageState extends State<GuidePage> {
  late List<Widget> _pageList;
  int index = 0;
  bool isNext = true;

  @override
  void initState() {
    // 引导页自带 BACK/NEXT 导航（无底栏布局），首次启动选语言时隐藏原生
    // HDS 底栏，避免其悬浮遮挡语言列表最后一项。
    // 锁定隐藏（引用计数）：引导页存活期间 Dart 层把任何来源的
    // setShellBarsHidden(false) 强制转成 true，原生底栏绝不显示。
    HarmonyChannel.setShellBarsLockHidden(true);
    shellBarsObserver.setForceHidden(true);
    // useNativeTabs 异步就绪（hdsController.init 完成）后补一次显隐同步
    hdsController.addListener(_onHdsChanged);
    _pageList = [InitPage(), NetworkPage()];
    super.initState();
  }

  /// useNativeTabs 就绪后再次确保引导页隐藏底栏。
  void _onHdsChanged() {
    if (!mounted || !hdsController.useNativeTabs) return;
    shellBarsObserver.setForceHidden(true);
  }

  @override
  void dispose() {
    // 离开引导页后解锁并恢复原生 HDS 底栏
    hdsController.removeListener(_onHdsChanged);
    HarmonyChannel.setShellBarsLockHidden(false);
    shellBarsObserver.setForceHidden(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: PageTransitionSwitcher(
                duration: const Duration(milliseconds: 300),
                reverse: !isNext,
                transitionBuilder:
                    (
                      Widget child,
                      Animation<double> animation,
                      Animation<double> secondaryAnimation,
                    ) {
                      return SharedAxisTransition(
                        child: child,
                        animation: animation,
                        secondaryAnimation: secondaryAnimation,
                        transitionType: SharedAxisTransitionType.horizontal,
                      );
                    },
                child: _pageList[index],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 15.0,
                vertical: 10,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  AnimatedOpacity(
                    duration: Duration(milliseconds: 300),
                    opacity: index == 0 ? 0 : 1,
                    child: TextButton(
                      onPressed: () {
                        int backValue = index - 1;
                        if (backValue == 1 || backValue == 0) {
                          setState(() {
                            index = backValue;
                            isNext = false;
                          });
                        }
                      },
                      child: const Text('BACK'),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      int nextValue = index + 1;
                      if (nextValue == 1) {
                        await Prefer.setInt(
                          'language_num',
                          userSetting.languageNum,
                        );
                        //有可能用户啥都没选
                        final languageList = Languages.map(
                          (e) => e.language,
                        ).toList();
                        ApiClient.Accept_Language =
                            languageList[userSetting.languageNum];
                        apiClient.httpClient.options.headers[HttpHeaders
                                .acceptLanguageHeader] =
                            ApiClient.Accept_Language;
                        setState(() {
                          index = nextValue;
                          isNext = true;
                        });
                      } else if (nextValue == 2) {
                        await Prefer.setBool('guide_enable', false);
                        Leader.pushUntilHome(context);
                      }
                    },
                    child: const Text('NEXT'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
