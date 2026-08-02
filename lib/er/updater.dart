import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:pixez/constants.dart';
import 'package:pixez/er/lprinter.dart';

enum Result { yes, no, timeout }

class Updater {
  static Result result = Result.timeout;
  static String? latestVersion;

  static Future<Result> check() async {
    if (Constants.isGooglePlay) return Result.no;
    final (result, version) = await compute(checkUpdate, "");
    Updater.result = result;
    Updater.latestVersion = version;
    return result;
  }
}

/// 返回 (检测结果, 远端最新版本号)；timeout 时版本号为 null。
/// 注意：本函数在 compute 生成的独立 isolate 中执行，静态变量不会回传主
/// isolate，因此必须把版本号作为返回值带出——否则主 isolate 的
/// Updater.latestVersion 恒为 null，导致新版本角标/提示永远不显示。
Future<(Result, String?)> checkUpdate(String arg) async {
  LPrinter.d("check for update ============");
  try {
    Response response = await Dio(
      BaseOptions(baseUrl: 'https://api.github.com'),
    ).get('/repos/bgli100/pixez-flutter-ohos/releases/latest');
    String tagName = response.data['tag_name'];
    LPrinter.d("tagName:$tagName ");
    if (tagName != Constants.tagName) {
      List<String> remoteList = tagName.split(".");
      List<String> localList = Constants.tagName.split(".");
      LPrinter.d("r:$remoteList l$localList");
      if (remoteList.length != localList.length) {
        return (Result.yes, tagName);
      }
      for (var i = 0; i < remoteList.length; i++) {
        int r = int.tryParse(remoteList[i]) ?? 0;
        int l = int.tryParse(localList[i]) ?? 0;
        LPrinter.d("r:$r l$l");
        if (r > l) return (Result.yes, tagName);
      }
    }
    return (Result.no, tagName);
  } catch (e) {
    print(e);
    return (Result.timeout, null);
  }
}
