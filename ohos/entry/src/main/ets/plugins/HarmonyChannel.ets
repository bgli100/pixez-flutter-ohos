/*
* Copyright (c) 2023 Hunan OpenValley Digital Industry Development Co., Ltd.
* Licensed under the Apache License, Version 2.0 (the "License");
* you may not use this file except in compliance with the License.
* You may obtain a copy of the License at
*
*     http://www.apache.org/licenses/LICENSE-2.0
*
* Unless required by applicable law or agreed to in writing, software
* distributed under the License is distributed on an "AS IS" BASIS,
* WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
* See the License for the specific language governing permissions and
* limitations under the License.
*/

import common from '@ohos.app.ability.common';import {
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodChannel,
  MethodResult,
} from "@ohos/flutter_ohos";

/**
  * 鸿蒙原生通道（HDS 沉浸光感导航栏适配）。
 *
  * Dart 侧通过 "harmonyChannel" MethodChannel 与本插件通信。
  * - getDeviceInfo          : 返回 { sdkApiVersion } 供 Dart 判断是否支持 HDS（>= 23）。
  * - setShellBars           : 是否启用原生 HDS 底栏（写 AppStorage 'useNativeTabs'）
  * - setShellBarsHidden     : 即时显隐（无动画，弹窗/全屏/子页面时隐藏）
  * - setShellBarsScrollHidden: 滚动动画显隐（写 AppStorage '__scrollHidden'）
  * - changeTabIndex         : Flutter 页签切换 -> eventHub 通知 Index.ets 的 HdsTabs
  * - setTabSelectedColor    : 同步主题色到 HdsTabs 选中态（写 AppStorage 'tabSelectedColor'）
 */
export default class HarmonyChannel implements FlutterPlugin {
  private channel: MethodChannel | null = null;

  getUniqueClassName(): string {
    return "HarmonyChannel";
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), "harmonyChannel");
    this.channel.setMethodCallHandler(this);
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.channel?.setMethodCallHandler(null);
  }

  public getChannel(): MethodChannel | null {
    return this.channel;
  }

  async onMethodCall(call: MethodCall, result: MethodResult): Promise<void> {
    switch (call.method) {
      case "getDeviceInfo": {
        result.success({ sdkApiVersion: 26 });
        break;
      }
      case "setShellBars": {
        const useNativeTabs: boolean = call.argument('useNativeTabs') ?? false;
        console.log(`HarmonyChannel: use native tabs = ${useNativeTabs}`);
        AppStorage.setOrCreate('useNativeTabs', useNativeTabs);
        result.success(true);
        break;
      }
      case "setShellBarsHidden": {
        const hidden: boolean = call.argument('hidden') ?? false;
        AppStorage.setOrCreate('shellBarsHidden', hidden);
        result.success(true);
        break;
      }
      case "setShellBarsScrollHidden": {
        const hidden: boolean = call.argument('hidden') ?? false;
        AppStorage.setOrCreate('__scrollHidden', hidden);
        result.success(true);
        break;
      }
      case "changeTabIndex": {
        const index: number = call.argument('index') ?? 0;
        const context = getContext() as common.UIAbilityContext;
        context.eventHub.emit('EVENT_CHANGE_TAB', index);
        result.success(true);
        break;
      }
      case "setTabSelectedColor": {
        const color: string = call.argument('color') ?? '#3367D6';
        AppStorage.setOrCreate('tabSelectedColor', color);
        result.success(true);
        break;
      }
      case "setShellTabMode": {
        // 切换底栏页签文案/图标：'main' 主界面 / 'novel' 小说模式
        const mode: string = call.argument('mode') ?? 'main';
        AppStorage.setOrCreate('shellTabMode', mode);
        result.success(true);
        break;
      }      case "setMiniBar": {
        // 迷你悬浮胶囊：收藏钮（favorite）/ 返回钮（back）
        const visible: boolean = call.argument('visible') ?? false;
        const icon: string = call.argument('icon') ?? 'favorite';
        const active: boolean = call.argument('active') ?? false;
        AppStorage.setOrCreate('miniBarVisible', visible);
        AppStorage.setOrCreate('miniBarIcon', icon);
        AppStorage.setOrCreate('miniBarActive', active);
        result.success(true);
        break;
      }
      default:
        result.notImplemented();
        break;
    }
  }
}

