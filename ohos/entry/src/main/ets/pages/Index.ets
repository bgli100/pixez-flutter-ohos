import common from '@ohos.app.ability.common';
import window from '@ohos.window';
import { FlutterPage } from '@ohos/flutter_ohos';
import { SymbolGlyphModifier } from '@kit.ArkUI';
import { HdsAnimationMode, hdsMaterial, HdsTabs, HdsTabsController } from '@kit.UIDesignKit';
import { Available } from '@kit.BasicServicesKit';

let storage = LocalStorage.getShared();
const EVENT_BACK_PRESS = 'EVENT_BACK_PRESS';
const TAG = 'Index';

// 底栏相关事件，由 EntryAbility 的 eventHub 监听
const EVENT_TAB_HOME = 'EVENT_TAB_HOME';
const EVENT_TAB_RANK = 'EVENT_TAB_RANK';
const EVENT_TAB_QUICK_VIEW = 'EVENT_TAB_QUICK_VIEW';
const EVENT_TAB_SEARCH = 'EVENT_TAB_SEARCH';
const EVENT_TAB_MORE = 'EVENT_TAB_MORE';

const EVENT_CHANGE_TAB = 'EVENT_CHANGE_TAB';
const EVENT_MINI_BAR_TAP = 'EVENT_MINI_BAR_TAP';

const NAV_UNSELECTED = $r('sys.color.comp_focused_primary');

const BOTTOM_NORMAL_AVOID_AREA_VALUE = 1;
const BOTTOM_SPECIAL_AVOID_AREA_VALUE = 12;

function tabSymbol(symbol: Resource, color: ResourceColor): SymbolGlyphModifier {
  return new SymbolGlyphModifier(symbol)
    .fontSize(22)
    .fontColor([color]);
}
interface ShellTabInfo {
  label: string
  symbol: Resource
}

// 主界面页签（沉浸光感底栏）
const SHELL_MAIN_TABS: ShellTabInfo[] = [
  { label: '首页', symbol: $r('sys.symbol.house_fill') },
  { label: '排行榜', symbol: $r('sys.symbol.discover_fill') },
  { label: '收藏', symbol: $r('sys.symbol.heart_fill') },
  { label: '搜索', symbol: $r('sys.symbol.magnifyingglass') },
  { label: '更多', symbol: $r('sys.symbol.ellipsis_circle') },
]

// 小说模式页签
const SHELL_NOVEL_TABS: ShellTabInfo[] = [
  { label: '首页', symbol: $r('sys.symbol.house_fill') },
  { label: '排行榜', symbol: $r('sys.symbol.discover_fill') },
  { label: '最新', symbol: $r('sys.symbol.clock') },
  { label: '搜索', symbol: $r('sys.symbol.magnifyingglass') },
  { label: '设置', symbol: $r('sys.symbol.gearshape_fill') },
]

@Entry(storage)
@Component
struct Index {
  private context = getContext(this) as common.UIAbilityContext
  @LocalStorageLink('viewId') viewId: string = "";
  @StorageLink('useNativeTabs') useNativeTabs: boolean = false;
  // 页面/弹窗切换时的即时显隐（无动画，由 Visibility 控制）
  @StorageLink('shellBarsHidden') shellBarsHidden: boolean = false;
  // 滚动时的动画显隐（有动画，由 @Watch 驱动）
  @StorageLink('__scrollHidden') @Watch('onScrollHiddenChanged') shellBarsScrollHidden: boolean = false;
  // 底栏选中色（由 Flutter 侧主题色同步）
  @StorageLink('tabSelectedColor') navSelected: string = '#3367D6';
  // 底栏页签模式（主界面 / 小说模式），由 Dart 侧经 setShellTabMode 切换
  @StorageLink('shellTabMode') shellTabMode: string = 'main';
  // 迷你悬浮胶囊（详情页收藏钮 / 小说模式返回钮），由 Flutter 侧控制
  @StorageLink('miniBarVisible') miniBarVisible: boolean = false
  @StorageLink('miniBarIcon') miniBarIcon: string = 'favorite'
  @StorageLink('miniBarActive') miniBarActive: boolean = false
  private miniController: HdsTabsController = new HdsTabsController();
  private lastMiniTapTime: number = 0;

  // 引擎的视口尺寸只跟随 XComponent surface 的 OnSurfaceChanged，而系统
  // 程序化改窗口（如全景多窗全屏走的 enableLandscapeMultiWindow）不会触发
  // ArkUI 重布局，surface 停在旧尺寸，Flutter 按旧窗口尺寸布局，右/下出现
  // 大片白区（手动拖动窗口会强制重布局所以能恢复）。这里监听窗口尺寸并把
  // 它显式绑定到根容器，用状态变化驱动重布局，让 surface 跟上窗口。
  @State winWidth: number = 0;
  @State winHeight: number = 0;
  private win: window.Window | null = null;
  private sizeCallback: ((size: window.Size) => void) | null = null;
  private rectCallback: ((opts: window.RectChangeOptions) => void) | null = null;
  // HdsTabs的controller
  private controller: HdsTabsController = new HdsTabsController();

  // 当前底部避让区变化
  @State bottomAvoidAreaHeight: number = 0;

  private applySize(widthPx: number, heightPx: number): void {
    this.winWidth = px2vp(widthPx);
    this.winHeight = px2vp(heightPx);
  }

  aboutToAppear(): void {
    // Flutter 发起的页签切换 → 同步 ArkTS HdsTabs 高亮
    this.context.eventHub.on(EVENT_CHANGE_TAB, (index: number) => {
      this.controller.changeIndex(index);
    });

    window.getLastWindow(this.context).then((w: window.Window) => {
      this.win = w;
      const rect = w.getWindowProperties().windowRect;
      this.applySize(rect.width, rect.height);
      this.sizeCallback = (size: window.Size) => {
        this.applySize(size.width, size.height);
      };
      w.on('windowSizeChange', this.sizeCallback);
      // windowSizeChange 对部分程序化窗口调整不回调，windowRectChange
      // (@since 12) 覆盖移动/缩放全部来源，双保险。
      try {
        this.rectCallback = (opts: window.RectChangeOptions) => {
          this.applySize(opts.rect.width, opts.rect.height);
        };
        w.on('windowRectChange', this.rectCallback);
      } catch (err) {
        console.error(TAG, `windowRectChange listener failed: ${err}`);
      }

      let windowBottomAvoidArea = w.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      let uiContext = this.getUIContext();
      // 如果下方有避让区，则只需添加正常情况下的避让offset，反而添加特殊情况下的避让offset，保证悬浮窗模式下的底栏可读性
      this.bottomAvoidAreaHeight = windowBottomAvoidArea.bottomRect.height === 0 ? BOTTOM_SPECIAL_AVOID_AREA_VALUE : (uiContext.px2vp(windowBottomAvoidArea.bottomRect.height) + BOTTOM_NORMAL_AVOID_AREA_VALUE);

      w.on('avoidAreaChange', (data) => {
        if (data.type === window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR) {
          // 如果下方有避让区，则只需添加正常情况下的避让offset，反而添加特殊情况下的避让offset，保证悬浮窗模式下的底栏可读性
          this.bottomAvoidAreaHeight = data.area.bottomRect.height === 0 ? BOTTOM_SPECIAL_AVOID_AREA_VALUE : (uiContext.px2vp(data.area.bottomRect.height) + BOTTOM_NORMAL_AVOID_AREA_VALUE);
        }
      });
    }).catch((err: Object) => {
      console.error(TAG, `getLastWindow failed: ${err}`);
    });
  }

  aboutToDisappear(): void {
    if (this.win !== null) {
      try {
        if (this.sizeCallback !== null) {
          this.win.off('windowSizeChange', this.sizeCallback);
        }
        if (this.rectCallback !== null) {
          this.win.off('windowRectChange', this.rectCallback);
        }
      } catch (err) {
        console.error(TAG, `off window listeners failed: ${err}`);
      }
      this.sizeCallback = null;
      this.rectCallback = null;
    }
  }

  // 滚动时的动画显隐回调
  onScrollHiddenChanged(): void {
    if (!this.useNativeTabs || this.shellBarsHidden) {
      return;
    }
    if (this.shellBarsScrollHidden) {
      this.controller.applyHideAnimation(HdsAnimationMode.SCROLL_ANIMATION);
    } else {
      this.controller.applyShowAnimation(HdsAnimationMode.SCROLL_ANIMATION);
    }
  }

  @Builder
  emptyTabContent() {
    Column()
      .width('100%')
      .height('100%')
  }

  @Builder
  hdsMainTabs() {
    HdsTabs({ controller: this.controller }) {
      if (this.shellTabMode === 'novel') {
        ForEach(SHELL_NOVEL_TABS, (tab: ShellTabInfo) => {
          TabContent() {
            this.emptyTabContent();
          }
          .tabBar(new BottomTabBarStyle({
            normal: tabSymbol(tab.symbol, NAV_UNSELECTED),
            selected: tabSymbol(tab.symbol, this.navSelected)
          }, tab.label).labelStyle({
            selectedColor: this.navSelected,
            unselectedColor: NAV_UNSELECTED
          }))
        }, (tab: ShellTabInfo) => tab.label)
      } else {
        ForEach(SHELL_MAIN_TABS, (tab: ShellTabInfo) => {
          TabContent() {
            this.emptyTabContent();
          }
          .tabBar(new BottomTabBarStyle({
            normal: tabSymbol(tab.symbol, NAV_UNSELECTED),
            selected: tabSymbol(tab.symbol, this.navSelected)
          }, tab.label).labelStyle({
            selectedColor: this.navSelected,
            unselectedColor: NAV_UNSELECTED
          }))
        }, (tab: ShellTabInfo) => tab.label)
      }
    }
    .onTabBarClick((index: number) => {
      // 通知 EntryAbility 切换 Flutter 页面
      if (index === 0) {
        this.context.eventHub.emit(EVENT_TAB_HOME);
      } else if (index === 1) {
        this.context.eventHub.emit(EVENT_TAB_RANK);
      } else if (index === 2) {
        this.context.eventHub.emit(EVENT_TAB_QUICK_VIEW);
      } else if (index === 3) {
        this.context.eventHub.emit(EVENT_TAB_SEARCH);
      } else {
        this.context.eventHub.emit(EVENT_TAB_MORE);
      }
    })
    .scrollable(false) // tab不可滑动
    .barOverlap(true)
    .barPosition(BarPosition.End)
    .vertical(false)
    .barFloatingStyle({
      barBottomMargin: this.bottomAvoidAreaHeight,
      adaptToHandedness: true,
      systemMaterialEffect: {
        materialType: hdsMaterial.MaterialType.IMMERSIVE,
        materialLevel: hdsMaterial.MaterialLevel.EXQUISITE
      }
    })
  }


  /// 迷你胶囊图标（favorite：心形/实心心形；back：返回箭头；
  /// refresh：刷新；close：关闭；delete：删除；photo：选图；fullscreen：退出全屏）
  miniIcon(): Resource {
    switch (this.miniBarIcon) {
      case 'back':
        return $r('sys.symbol.arrow_left');
      case 'refresh':
        return $r('sys.symbol.arrow_clockwise');
      case 'close':
        return $r('sys.symbol.xmark');
      case 'delete':
        return $r('sys.symbol.trash');
      case 'photo':
        return $r('sys.symbol.camera');
      case 'fullscreen':
        return $r('sys.symbol.arrow_down_right_and_arrow_up_left');
      default:
        return this.miniBarActive ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart');
    }
  }
  /// 迷你栏图标颜色（收藏激活时红色）
  miniColor(): ResourceColor {
    if (this.miniBarIcon === 'favorite' && this.miniBarActive) {
      return Color.Red;
    }
    return this.navSelected;
  }


  /// 迷你栏点击去重：onTabBarClick 与 onClick 双保险，防止同一触摸重复触发
  emitMiniTap() {
    const now = Date.now();
    if (now - this.lastMiniTapTime < 400) return;
    this.lastMiniTapTime = now;
    this.context.eventHub.emit(EVENT_MINI_BAR_TAP);
  }

  /// 迷你栏：用 HdsTabs 单页签做正圆形按钮（详情页收藏钮 / 小说模式返回钮）。
  /// 官方 tab 控件会正确消费触摸（不穿透到 Flutter 层，避免同时点到下层按钮），
  /// systemMaterialEffect 提供与主栏一致的沉浸光感材质。
  @Builder
  miniBarCapsule() {
    HdsTabs({ controller: this.miniController }) {
      TabContent() {
        this.emptyTabContent();
      }
      .tabBar(new BottomTabBarStyle({
        normal: tabSymbol(this.miniIcon(), this.miniColor()),
        selected: tabSymbol(this.miniIcon(), this.miniColor())
      }, '').labelStyle({
        selectedColor: this.miniColor(),
        unselectedColor: this.miniColor()
      }))
    }
    .onTabBarClick((index: number) => {
      // 迷你栏点击 → 通知 Flutter（详情页收藏 / 小说模式返回）
      this.emitMiniTap();
    })
    .onClick(() => {
      this.emitMiniTap();
    })
    .scrollable(false)
    .barOverlap(true)
    .barPosition(BarPosition.End)
    .vertical(false)
    .barWidth(56)
    .barHeight(56)
    .barFloatingStyle({
      barBottomMargin: 0,
      barSideMargin: 0,
      systemMaterialEffect: {
        materialType: hdsMaterial.MaterialType.IMMERSIVE,
        materialLevel: hdsMaterial.MaterialLevel.EXQUISITE
      }
    })
    .width(56)
    .height(56)
    .borderRadius(28)
    .clip(true)
  }
  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      FlutterPage({ viewId: this.viewId })
        .width('100%')
        .height('100%')
      if (this.useNativeTabs) {
        Column() {
          this.hdsMainTabs()
        }
        .hitTestBehavior(HitTestMode.Transparent) // 透传触控操作，防止影响flutter层触摸
        .width('100%')
        .height('100%')
        // 页面/弹窗切换时即时隐藏，无动画；迷你栏激活时保持显示（详情页/小说模式）
        .visibility(this.shellBarsHidden ? Visibility.None : Visibility.Visible)
      }
      // 迷你栏：独立悬浮胶囊（详情页收藏钮 / 小说模式返回钮），浮于右下。
      // 容器始终渲染（预热 HdsTabs，避免首次创建时单页签 onTabBarClick 未就绪导致点无反应），
      // 由 miniBarVisible 控制显隐与命中。
      // 隐藏时必须用 Visibility.None 彻底移出命中测试：仅 hitTestBehavior(None) + opacity(0)
      // 不够——HdsTabs 自带的 onClick/onTabBarClick 触摸区域仍会拦截右下角触摸，
      // 挡住大图页（PhotoZoomPage）底栏最右侧的 HD 钮（而左侧分享钮正常）。
      if (this.useNativeTabs) {
        Stack() {
          this.miniBarCapsule()
        }
        .width(56)
        .height(56)
        .position({
          right: 20,
          bottom: this.bottomAvoidAreaHeight + (this.shellBarsHidden ? 24 : 80)
        })
        .visibility(this.miniBarVisible ? Visibility.Visible : Visibility.None)
        .hitTestBehavior(this.miniBarVisible ? HitTestMode.Default : HitTestMode.None)
        .opacity(this.miniBarVisible ? 1 : 0)
      }
    }
    .width(this.winWidth > 0 ? this.winWidth : '100%')
    .height(this.winHeight > 0 ? this.winHeight : '100%')
  }
  onBackPress(): boolean {
    this.context.eventHub.emit(EVENT_BACK_PRESS)
    return true
  }
}












