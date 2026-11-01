/*
 * Copyright (C) 2020. by perol_notsf, All rights reserved
 *
 * This program is free software: you can redistribute it and/or modify it under
 * the terms of the GNU General Public License as published by the Free Software
 * Foundation, either version 3 of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along with
 * this program. If not, see <http://www.gnu.org/licenses/>.
 *
 */

import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// 纯 Dart 合成动图 GIF。
///
/// 原生编码通道（`samples.flutter.dev/battery`）只在 Android/iOS 注册，
/// 鸿蒙端没有任何实现，因此这里用 `package:image` 的 [img.GifEncoder] 兜底。
/// 解码与量化的开销较大，放到后台 isolate 执行，避免卡住 UI。
///
/// [framePaths] 需按播放顺序排列，[delays] 为每帧时长（毫秒）。
Future<Uint8List> encodeUgoiraGif({
  required List<String> framePaths,
  required List<int> delays,
  int fallbackDelay = 80,
}) {
  if (framePaths.isEmpty) {
    throw ArgumentError.value(framePaths, "framePaths", "no frame to encode");
  }
  return Isolate.run(
    () => _encodeUgoiraGif(framePaths, List<int>.of(delays), fallbackDelay),
  );
}

Uint8List _encodeUgoiraGif(
  List<String> framePaths,
  List<int> delays,
  int fallbackDelay,
) {
  // repeat 0 = 无限循环；addFrame 的 duration 单位是 1/100 秒。
  final encoder = img.GifEncoder(
    repeat: 0,
    quantizerType: img.QuantizerType.octree,
  );
  for (var i = 0; i < framePaths.length; i++) {
    final frame = img.decodeImage(File(framePaths[i]).readAsBytesSync());
    if (frame == null) {
      throw FormatException("unsupported ugoira frame: ${framePaths[i]}");
    }
    final delayMs = i < delays.length ? delays[i] : fallbackDelay;
    encoder.addFrame(frame, duration: math.max(1, (delayMs / 10).round()));
  }
  final bytes = encoder.finish();
  if (bytes == null || bytes.isEmpty) {
    throw StateError("gif encoding produced no data");
  }
  return bytes;
}
