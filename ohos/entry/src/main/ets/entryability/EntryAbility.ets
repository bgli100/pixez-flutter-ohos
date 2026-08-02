import AbilityConstant from "@ohos.app.ability.AbilityConstant";
import type Want from "@ohos.app.ability.Want";
import window from "@ohos.window";
import { FlutterAbility, FlutterEngine, MethodChannel } from "@ohos/flutter_ohos";
import { GeneratedPluginRegistrant } from "../plugins/GeneratedPluginRegistrant";
import HarmonyChannel from "../plugins/HarmonyChannel";

/// 底栏相关事件，与 Index.ets 保持一致
const EVENT_TAB_HOME = 'EVENT_TAB_HOME';
const EVENT_TAB_RANK = 'EVENT_TAB_RANK';
const EVENT_TAB_QUICK_VIEW = 'EVENT_TAB_QUICK_VIEW';
const EVENT_TAB_SEARCH = 'EVENT_TAB_SEARCH';
const EVENT_TAB_MORE = 'EVENT_TAB_MORE';
const EVENT_MINI_BAR_TAP = 'EVENT_MINI_BAR_TAP';


export default class EntryAbility extends FlutterAbility {
  harmonyChannel: HarmonyChannel = new HarmonyChannel();
  private flutterChannel: MethodChannel | null = null;
  private envChangeListener: number | null = null;

  configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine);
    GeneratedPluginRegistrant.registerWith(flutterEngine);
    flutterEngine.getPlugins()?.add(this.harmonyChannel);
    this.flutterChannel = this.harmonyChannel.getChannel();
    this.initFontWeightListener();
    this.initShellEventListeners();
  }

  /// 监听 Index.ets eventHub 的底栏切换事件，转发给 Flutter
  private initShellEventListeners(): void {
    this.context.eventHub.on(EVENT_TAB_HOME, () => {
      this.flutterChannel?.invokeMethod('showHome', null);
    });
    this.context.eventHub.on(EVENT_TAB_RANK, () => {
      this.flutterChannel?.invokeMethod('showRank', null);
    });
    this.context.eventHub.on(EVENT_TAB_QUICK_VIEW, () => {
      this.flutterChannel?.invokeMethod('showQuickView', null);
    });
    this.context.eventHub.on(EVENT_TAB_SEARCH, () => {
      this.flutterChannel?.invokeMethod('showSearch', null);
    });
    this.context.eventHub.on(EVENT_TAB_MORE, () => {
      this.flutterChannel?.invokeMethod('showMore', null);
    });
    // 迷你胶囊点击监听：必须作为独立顶层注册（曾误嵌套进 EVENT_TAB_MORE
    // 回调内，导致启动时未注册——首次进详情页点收藏无反应，直到点过"更多"
    // 页签（进小说模式的必经路径）才注册上，表现为"去一趟小说模式才能用"）
    this.context.eventHub.on(EVENT_MINI_BAR_TAP, () => {
      this.flutterChannel?.invokeMethod('miniBarTap', null);
    });
  }

  private initFontWeightListener(): void {
    // 监听系统字重变化
    this.envChangeListener = this.context.getApplicationContext().on('environment', {
      onConfigurationUpdated: (config) => {
        const fontWeightScale = config.fontWeightScale;
        console.info(`EntryAbility: fontWeightScale changed to ${fontWeightScale}`);
        this.flutterChannel?.invokeMethod("onFontWeightScaleChange", { fontWeightScale: fontWeightScale });
      },
      onMemoryLevel: () => {
      }
    });

    // 获取初始系统字重值
    const initialFontWeightScale = this.context.config.fontWeightScale;
    console.info(`EntryAbility: initial fontWeightScale is ${initialFontWeightScale}`);
    this.flutterChannel?.invokeMethod("onFontWeightScaleChange", { fontWeightScale: initialFontWeightScale });
  }

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam) {
    AppStorage.setOrCreate('shellBarsHidden', false);
    AppStorage.setOrCreate('__scrollHidden', false);
    // 底栏页签模式默认主界面
    AppStorage.setOrCreate('shellTabMode', 'main');

    super.onCreate(want, launchParam);
  }

  async onWindowStageCreate(windowStage: window.WindowStage): Promise<void> {
    super.onWindowStageCreate(windowStage);
  }

  onDestroy(): void {
    if (this.envChangeListener !== null) {
      this.context.getApplicationContext().off('environment', this.envChangeListener);
    }
    super.onDestroy();
  }
}



