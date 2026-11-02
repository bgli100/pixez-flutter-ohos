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
import 'package:archive/archive.dart';
import 'package:bot_toast/bot_toast.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:mobx/mobx.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pixez/er/hoster.dart';
import 'package:pixez/er/pixiv_image_source.dart';
import 'package:pixez/er/lprinter.dart';
import 'package:pixez/main.dart';
import 'package:pixez/models/ugoira_metadata_response.dart';
import 'package:pixez/network/api_client.dart';
import 'package:pixez/document_plugin.dart';
import 'package:pixez/saf_plugin.dart';
import 'package:pixez/models/illust.dart';
import 'package:pixez/page/picture/illust_store.dart';
import 'package:pixez/page/picture/ugoira_gif_encoder.dart';
import 'package:pixez/store/save_store.dart';

part 'ugoira_store.g.dart';

enum UgoiraStatus { pre, progress, play }

class UgoiraStore = _UgoiraStoreBase with _$UgoiraStore;

abstract class _UgoiraStoreBase with Store {
  final int id;

  _UgoiraStoreBase(this.id);

  @observable
  UgoiraStatus? status;
  @observable
  int count = 0;
  @observable
  int total = 1;
  @observable
  bool isEncoding = false;

  static const _platform = const MethodChannel('samples.flutter.dev/battery');

  List<FileSystemEntity> drawPool = [];
  UgoiraMetadataResponse? ugoiraMetadataResponse;

  Future<void> export(Illusts illusts) async {
    try {
      Directory tempDir = await getTemporaryDirectory();
      String tempPath = tempDir.path;
      String fullPath = "$tempPath/${id}.zip";
      File fullPathFile = File(fullPath);
      if (fullPathFile.existsSync()) {
        final data = fullPathFile.readAsBytesSync();
        String zipFileName = await buildSaveFileName(illusts, 0, ".zip");
        zipFileName = applySingleFolder(illusts, zipFileName);
        if (Platform.isAndroid || Platform.isOhos) {
          try {
            String? uriString = await SAFPlugin.createFile(
              zipFileName,
              "application/zip",
            );
            uriString!;
            await SAFPlugin.writeUri(uriString, data);
            BotToast.showText(text: "export success");
            return;
          } catch (e) {
            BotToast.showText(text: "export cancelled");
            return;
          }
        }
        final success = await DocumentPlugin.save(data, zipFileName);
        if (success == true) {
          BotToast.showText(text: "export success");
        } else {
          BotToast.showText(text: "export failed");
        }
      } else {
        BotToast.showText(text: "zip file not found, please download first");
      }
    } catch (e) {
      LPrinter.d(e);
      BotToast.showText(text: "export error: ${e.toString()}");
    }
  }

  @action
  Future<void> encodeGif(Illusts illusts) async {
    if (isEncoding) return;
    if (drawPool.isEmpty || ugoiraMetadataResponse == null) {
      BotToast.showText(text: "not ready");
      return;
    }
    try {
      isEncoding = true;
      final gifName = await buildSaveFileName(illusts, 0, ".gif");
      if (Platform.isOhos) {
        await _encodeGifOnOhos(illusts, gifName);
        return;
      }
      BotToast.showText(text: "[Encoding] $gifName");
      final gifPath = await _platform.invokeMethod('getBatteryLevel', {
        "path": drawPool.first.parent.path, // guarded by isEmpty check above
        "delay": ugoiraMetadataResponse!.ugoiraMetadata.frames.first.delay,
        "delay_array": ugoiraMetadataResponse!.ugoiraMetadata.frames
            .map((e) => e.delay)
            .toList(),
      });
      if (gifPath != null) {
        final targetName = applySingleFolder(illusts, gifName);
        await DocumentPlugin.saveFromPath(gifPath, targetName);
        BotToast.showText(text: "[GifSaved] $gifName");
        await _autoBookmarkAfterSave(illusts);
      }
    } catch (e) {
      LPrinter.d(e);
      BotToast.showText(
        text: "encode failed: ${e is PlatformException ? e.message : e}",
      );
    } finally {
      isEncoding = false;
    }
  }

  /// 鸿蒙端的 GIF 导出：编码交给原生 `libugoiragif.so`（`pixez/ugoira_gif`
  /// 通道，与安卓端同一套 GCTGifEncoder），只在开始/结束时各弹一条 toast，
  /// 编码期间不阻塞界面（与 Android 端一致）。
  Future<void> _encodeGifOnOhos(Illusts illusts, String gifName) async {
    final frames = _framePaths();
    if (frames.isEmpty) {
      BotToast.showText(text: "not ready");
      return;
    }
    BotToast.showText(text: "[Encoding] $gifName");
    final tempDir = await getTemporaryDirectory();
    final outputPath =
        "${tempDir.path}/ugoira_${id}_"
        "${DateTime.now().millisecondsSinceEpoch}.gif";
    File? encoded;
    try {
      final gifPath = await encodeUgoiraGifFile(
        framePaths: frames,
        delays: ugoiraMetadataResponse!.ugoiraMetadata.frames
            .map((e) => e.delay)
            .toList(),
        outputPath: outputPath,
      );
      encoded = File(gifPath);
      final bytes = await encoded.readAsBytes();
      // 相册插件用 name.split('.') 拆分扩展名与标题，标题里的点会让扩展名解析失败，
      // 这里只保留扩展名前的那一个点。
      final result = await ImageGallerySaver.saveImage(
        bytes,
        name: _galleryName(gifName),
      );
      if (result is Map && result["isSuccess"] == true) {
        BotToast.showText(text: "[GifSaved] $gifName");
        await _autoBookmarkAfterSave(illusts);
      } else {
        final message = result is Map ? result["message"] : result;
        BotToast.showText(text: "encode failed: $message");
      }
    } catch (e) {
      LPrinter.d(e);
      BotToast.showText(
        text: "encode failed: ${e is PlatformException ? e.message : e}",
      );
    } finally {
      // 相册里已经有一份，缓存文件不再需要
      try {
        if (encoded != null && encoded.existsSync()) encoded.deleteSync();
      } catch (_) {}
    }
  }

  String _galleryName(String gifName) {
    final dot = gifName.lastIndexOf(".");
    if (dot < 0) return "$gifName.gif";
    final base = gifName.substring(0, dot).replaceAll(".", "_");
    return "$base${gifName.substring(dot)}";
  }

  List<String> _framePaths() {
    return drawPool.whereType<File>().map((e) => e.path).where((path) {
      final lower = path.toLowerCase();
      return lower.endsWith(".jpg") ||
          lower.endsWith(".jpeg") ||
          lower.endsWith(".png");
    }).toList()..sort();
  }

  Future<void> _autoBookmarkAfterSave(Illusts illusts) async {
    if (!userSetting.starAfterSave) return;
    final illustStore = IllustStore(illusts.id, illusts);
    if (illustStore.state != 0) return;
    final success = await illustStore.star(
      restrict: userSetting.defaultPrivateLike ? "private" : "public",
    );
    if (success && userSetting.followAfterStar) {
      await illustStore.followAfterStar();
    }
  }

  @action
  unZip() async {
    Directory tempDir = await getTemporaryDirectory();
    String tempPath = tempDir.path;
    String fullPath = "$tempPath/${id}.zip";
    File fullPathFile = File(fullPath);
    try {
      // Read the Zip file from disk.
      final bytes = fullPathFile.readAsBytesSync();

      // Decode the Zip file
      final archive = ZipDecoder().decodeBytes(bytes);

      // Extract the contents of the Zip archive to disk.
      for (final file in archive) {
        final filename = file.name;
        if (file.isFile) {
          final data = file.content as List<int>;
          File('$tempPath/$id/' + filename)
            ..createSync(recursive: true)
            ..writeAsBytesSync(data);
        } else {
          Directory('$tempPath/$id/' + filename)..create(recursive: true);
        }
      }
      Directory zipDirectory = Directory('$tempPath/$id/');
      var listSync = zipDirectory.listSync();
      listSync.sort((l, r) => l.path.compareTo(r.path));
      drawPool = listSync;
      status = UgoiraStatus.play;
    } catch (e) {
      if (fullPathFile.existsSync()) fullPathFile.deleteSync();
      if (Directory('$tempPath/$id/').existsSync()) {
        Directory('$tempPath/$id/').deleteSync(recursive: true);
      }
      status = UgoiraStatus.pre;
    }
  }

  @action
  downloadAndUnzip() async {
    status = UgoiraStatus.progress;
    Directory tempDir = await getTemporaryDirectory();
    String tempPath = tempDir.path;
    String fullPath = "$tempPath/$id.zip";
    File fullPathFile = File(fullPath);
    try {
      ugoiraMetadataResponse = await apiClient.getUgoiraMetadata(id);
      String zipUrl = ugoiraMetadataResponse!.ugoiraMetadata.zipUrls.medium;
      final sourceZipUrl = PixivImageSource.resolve(
        zipUrl,
        networkMode: userSetting.networkMode,
        pictureSource: userSetting.pictureSource,
      );
      if (!fullPathFile.existsSync()) {
        var dio = Dio(
          BaseOptions(
            headers: Hoster.header(
              url: ugoiraMetadataResponse!.ugoiraMetadata.zipUrls.medium,
            ),
          ),
        );
        if (userSetting.networkMode.usesCompatibleConnection) {
          dio.httpClientAdapter = await ApiClient.createCompatibleClient();
        }
        dio.download(
          sourceZipUrl,
          fullPath,
          onReceiveProgress: (int count, int total) {
            this.count = count;
            this.total = total;
            if (count / total == 1) {
              unZip();
            }
          },
          deleteOnError: true,
        );
      } else {
        unZip();
      }
    } catch (e) {
      if (fullPathFile.existsSync()) fullPathFile.deleteSync();
      if (Directory('$tempPath/$id/').existsSync()) {
        Directory('$tempPath/$id/').deleteSync(recursive: true);
      }
      status = UgoiraStatus.pre;
    }
  }
}
