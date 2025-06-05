import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:pixez/constants.dart';
import 'package:pixez/er/lprinter.dart';

enum Result { yes, no, timeout }

class Updater {
  static Result result = Result.timeout;

  static Future<Result> check() async {
    if (Constants.isGooglePlay) return Result.no;
    final result = await compute(checkUpdate, "");
    Updater.result = result;
    return result;
  }
}

Future<Result> checkUpdate(String arg) async {
  LPrinter.d("check for update ============");
  try {
    Response response =
        await Dio(BaseOptions(baseUrl: 'https://api.github.com'))
            .get('/repos/bgli100/pixez-flutter-ohos/releases/latest');
    String tagName = response.data['tag_name'];
    LPrinter.d("tagName:$tagName ");
    if (tagName != Constants.tagName) {
      List<String> remoteList = tagName.split(".");
      List<String> localList = Constants.tagName.split(".");
      LPrinter.d("r:$remoteList l$localList");
      if (remoteList.length != localList.length) return Result.yes;
      for (var i = 0; i < remoteList.length; i++) {
        int r = int.tryParse(remoteList[i]) ?? 0;
        int l = int.tryParse(localList[i]) ?? 0;
        LPrinter.d("r:$r l$l");
        if (r > l) return Result.yes;
      }
    }
  } catch (e) {
    print(e);
    return Result.timeout;
  }
  return Result.no;
}
