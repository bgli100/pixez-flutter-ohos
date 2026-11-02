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

import {
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodChannel,
  MethodResult,
} from "@ohos/flutter_ohos";
import ugoiraGif from "libugoiragif.so";

const CHANNEL_NAME = "pixez/ugoira_gif";

interface UgoiraGifModule {
  encodeGif(
    framePaths: string[],
    delays: number[],
    outputPath: string,
  ): Promise<string>;
}

const gifEncoder: UgoiraGifModule = ugoiraGif as UgoiraGifModule;

/**
 * 动图（ugoira）GIF 编码通道。
 *
 * Dart 侧通过 "pixez/ugoira_gif" MethodChannel 调用：
 * - encodeGif(framePaths, delays, outputPath) -> outputPath
 *
 * 编码在原生 `libugoiragif.so` 里完成（NAPI async work）：
 * - 复用安卓端同一份 GCTGifEncoder：全动画共享一张 255 色全局调色板 +
 *   Floyd–Steinberg 抖动，调色板条目保持完整 8bit；
 * - JPEG 解码走系统 image framework（libjpeg），像素读回后直接编码，不经过 JS；
 * - 全程不占用 UI 线程。
 *
 * 不用 `ImagePacker.packToFileFromPixelmapSequence`：系统实现按 5bit/通道量化、
 * 不做抖动、且每帧重算一张 local color table，表现为渐变硬色带 + 帧间颜色闪烁。
 */
export default class UgoiraGifEncoder implements FlutterPlugin {
  private channel: MethodChannel | null = null;

  getUniqueClassName(): string {
    return "UgoiraGifEncoder";
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(
      binding.getBinaryMessenger(),
      CHANNEL_NAME,
    );
    this.channel.setMethodCallHandler(this);
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.channel?.setMethodCallHandler(null);
  }

  async onMethodCall(call: MethodCall, result: MethodResult): Promise<void> {
    if (call.method !== "encodeGif") {
      result.notImplemented();
      return;
    }
    try {
      const framePaths = call.argument("framePaths") as string[];
      const delays = call.argument("delays") as number[];
      const outputPath = call.argument("outputPath") as string;
      const gifPath = await gifEncoder.encodeGif(
        framePaths,
        delays,
        outputPath,
      );
      result.success(gifPath);
    } catch (e) {
      console.error(`UgoiraGifEncoder: encode failed: ${JSON.stringify(e)}`);
      result.error(
        "ENCODE_FAILED",
        "GIF encoding failed: " + JSON.stringify(e),
        null,
      );
    }
  }
}
