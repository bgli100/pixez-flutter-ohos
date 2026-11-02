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

import 'package:flutter/services.dart';

/// 鸿蒙原生 GIF 编码通道（ArkTS 侧转发到 `libugoiragif.so`，
/// 源码见 `ohos/entry/src/main/cpp/`）。
const MethodChannel _channel = MethodChannel('pixez/ugoira_gif');

/// 把 ugoira 帧序列编码成 GIF 文件，返回 GIF 文件的路径。
///
/// 编码全部在原生侧完成：JPEG 解码 + 与安卓端同一套 GCTGifEncoder
/// （全局 255 色调色板 + Floyd–Steinberg 抖动）+ LZW，全程在 native 工作线程，
/// 不占用 UI 线程。编码失败时抛出 [PlatformException]（通道缺失时为
/// [MissingPluginException]），由调用方提示用户。
///
/// [framePaths] 需按播放顺序排列，[delays] 为每帧时长（毫秒），
/// [outputPath] 是 GIF 的落盘位置。
Future<String> encodeUgoiraGifFile({
  required List<String> framePaths,
  required List<int> delays,
  required String outputPath,
}) async {
  if (framePaths.isEmpty) {
    throw ArgumentError.value(framePaths, "framePaths", "no frame to encode");
  }
  final path = await _channel.invokeMethod<String>('encodeGif', {
    'framePaths': framePaths,
    'delays': delays,
    'outputPath': outputPath,
  });
  if (path == null || path.isEmpty) {
    throw StateError("gif encoding produced no file");
  }
  return path;
}
