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

import 'package:bot_toast/bot_toast.dart';
import 'package:easy_refresh/easy_refresh.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:pixez/component/fluent/ban_page.dart';
import 'package:pixez/component/null_hero.dart';
import 'package:pixez/component/fluent/painter_avatar.dart';
import 'package:pixez/component/fluent/pixiv_image.dart';
import 'package:pixez/component/selectable_html.dart';
import 'package:pixez/er/leader.dart';
import 'package:pixez/er/lprinter.dart';
import 'package:pixez/exts.dart';
import 'package:pixez/i18n.dart';
import 'package:pixez/main.dart';
import 'package:pixez/models/ban_illust_id.dart';
import 'package:pixez/models/ban_tag.dart';
import 'package:pixez/models/illust.dart';
import 'package:pixez/page/fluent/comment/comment_page.dart';
import 'package:pixez/page/picture/illust_about_store.dart';
import 'package:pixez/page/picture/illust_store.dart';
import 'package:pixez/page/fluent/picture/picture_list_page.dart';
import 'package:pixez/page/fluent/picture/tag_for_illust_page.dart';
import 'package:pixez/page/fluent/picture/ugoira_loader.dart';
import 'package:pixez/page/fluent/search/result_page.dart';
import 'package:pixez/page/user/user_store.dart';
import 'package:pixez/page/fluent/user/users_page.dart';
import 'package:pixez/page/fluent/zoom/photo_zoom_page.dart';
import 'package:share_plus/share_plus.dart';

class IllustRowPage extends StatefulWidget {
  final int id;
  final String? heroString;
  final IllustStore? store;

  const IllustRowPage({Key? key, required this.id, this.heroString, this.store})
      : super(key: key);

  @override
  _IllustRowPageState createState() => _IllustRowPageState();
}

class _IllustRowPageState extends State<IllustRowPage>
    with AutomaticKeepAliveClientMixin {
  UserStore? userStore;
  late IllustStore _illustStore;
  late IllustAboutStore _aboutStore;
  late ScrollController _scrollController;
  late EasyRefreshController _refreshController;
  bool tempView = false;

  @override
  void initState() {
    // widget.relay.more =
    //     () => buildshowBottomSheet(context, _illustStore.illusts!);

    _refreshController = EasyRefreshController(
        controlFinishLoad: true, controlFinishRefresh: true);
    _scrollController = ScrollController();
    _illustStore = widget.store ?? IllustStore(widget.id, null);
    _illustStore.fetch();
    _aboutStore =
        IllustAboutStore(widget.id, refreshController: _refreshController);

    // Load More Detecter
    _scrollController.addListener(() {
      if (_scrollController.position.pixels + 300 >
          _scrollController.position.maxScrollExtent) {
        _refreshController.callLoad();
      }
    });
    super.initState();
  }

  @override
  void didUpdateWidget(covariant IllustRowPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      _illustStore = widget.store ?? IllustStore(widget.id, null);
      _illustStore.fetch();
      _aboutStore = IllustAboutStore(widget.id);
      LPrinter.d("state change");
    }
  }

  void _loadAbout() {
    if (mounted &&
        _scrollController.hasClients &&
        _scrollController.offset + 180 >=
            _scrollController.position.maxScrollExtent &&
        _aboutStore.illusts.isEmpty) _aboutStore.fetch();
  }

  @override
  void dispose() {
    _illustStore.dispose();
    _scrollController.dispose();
    _refreshController.dispose();
    super.dispose();
  }

  Widget _buildAppbar() {
    return Column(
      children: [
        Container(
          height: MediaQuery.of(context).padding.top,
        ),
        Container(
          child: Row(
            mainAxisSize: MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              IconButton(
                  icon: Icon(FluentIcons.back),
                  onPressed: () {
                    Navigator.of(context).pop();
                  }),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                      icon: Icon(FluentIcons.more_vertical),
                      onPressed: () {
                        buildshowBottomSheet(context, _illustStore.illusts!);
                      })
                ],
              )
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ScaffoldPage(
      // TODO
      // extendBody: true,
      // header: PageHeader(
      //   elevation: 0.0,
      //   // iconTheme: IconTheme.of(context).copyWith(color: FluentTheme.of(context).typography!.bodyText1!.color),
      //   backgroundColor: Colors.transparent,
      //   actions: [
      //     IconButton(
      //         icon: Icon(FluentIcons.more_vert),
      //         onPressed: () {
      //           buildshowBottomSheet(context, _illustStore.illusts!);
      //         })
      //   ],
      // ),
      // extendBodyBehindAppBar: true,
      // floatingActionButton: GestureDetector(
      //   onLongPress: () {
      //     _showBookMarkTag();
      //   },
      //   child: Observer(builder: (context) {
      //     return Visibility(
      //       visible: _illustStore.errorMessage == null,
      //       child: FloatingActionButton(
      //         heroTag: widget.id,
      //         backgroundColor: Colors.white,
      //         onPressed: () => _illustStore.star(),
      //         child: Observer(builder: (_) {
      //           return StarIcon(
      //             state: _illustStore.state,
      //           );
      //         }),
      //       ),
      //     );
      //   }),
      // ),
      content: Observer(builder: (_) {
        if (!tempView)
          for (var i in muteStore.banillusts) {
            if (i.illustId == widget.id.toString()) {
              return BanPage(
                name: "${I18n.of(context).illust}\n${i.name}\n",
                onPressed: () {
                  setState(() {
                    tempView = true;
                  });
                },
              );
            }
          }
        if (!tempView && _illustStore.illusts != null) {
          for (var j in muteStore.banUserIds) {
            if (j.userId == _illustStore.illusts!.user.id.toString()) {
              return BanPage(
                name: "${I18n.of(context).painter}\n${j.name}\n",
                onPressed: () {
                  setState(() {
                    tempView = true;
                  });
                },
              );
            }
          }
          for (var t in muteStore.banTags) {
            for (var t1 in _illustStore.illusts!.tags) {
              if (t.name == t1.name)
                return BanPage(
                  name: "${I18n.of(context).tag}\n${t.name}\n",
                  onPressed: () {
                    setState(() {
                      tempView = true;
                    });
                  },
                );
            }
          }
        }
        return Container(
          child: Stack(
            children: [
              _buildContent(context, _illustStore.illusts),
              _buildAppbar()
            ],
          ),
        );
      }),
    );
  }

  Widget colorText(String text, BuildContext context) => Text(
        text,
        style: TextStyle(color: FluentTheme.of(context).accentColor),
      );

  ScrollController scrollController = ScrollController();

  Widget _buildContent(BuildContext context, Illusts? data) {
    if (_illustStore.errorMessage != null) return _buildErrorContent(context);
    if (data == null)
      return Container(
        child: Center(
          child: ProgressRing(),
        ),
      );
    var expectWidth = MediaQuery.of(context).size.width * 0.7;
    var leftWidth = MediaQuery.of(context).size.width - expectWidth;
    final atLeastWidth = 320.0;
    if (leftWidth < atLeastWidth) {
      leftWidth = atLeastWidth;
      expectWidth = MediaQuery.of(context).size.width - leftWidth;
    }
    final radio = (data.height.toDouble() / data.width);
    final screenHeight = MediaQuery.of(context).size.height;
    final height = (radio * expectWidth);
    final centerType = height <= screenHeight;

    var imageWidth = MediaQuery.of(context).size.width - 300 - 320;

    return Container(
      child: Stack(
        children: [
          Row(
            children: [
              Container(
                width: imageWidth > 300 ? imageWidth : expectWidth,
                child: CustomScrollView(
                    slivers: [..._buildPhotoList(data, centerType, height)]),
              ),
              Expanded(
                child: Container(
                  color: FluentTheme.of(context).cardColor,
                  child: EasyRefresh(
                    controller: _refreshController,
                    onLoad: () {
                      _aboutStore.next();
                    },
                    child: CustomScrollView(
                      controller: _scrollController,
                      slivers: [
                        SliverToBoxAdapter(
                            child: Container(
                                height: MediaQuery.of(context).padding.top)),
                        SliverToBoxAdapter(
                          child: _buildNameAvatar(context, data),
                        ),
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Column(
                              children: <Widget>[
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.start,
                                  children: <Widget>[
                                    Text(I18n.of(context).illust_id),
                                    Container(
                                      width: 10.0,
                                    ),
                                    colorText(data.id.toString(), context),
                                    Container(
                                      width: 20.0,
                                    ),
                                    Text(I18n.of(context).pixel),
                                    Container(
                                      width: 10.0,
                                    ),
                                    colorText(
                                        "${data.width}x${data.height}", context)
                                  ],
                                ),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.start,
                                  children: <Widget>[
                                    Text(I18n.of(context).total_view),
                                    Container(
                                      width: 10.0,
                                    ),
                                    colorText(
                                        data.totalView.toString(), context),
                                    Container(
                                      width: 20.0,
                                    ),
                                    Text(I18n.of(context).total_bookmark),
                                    Container(
                                      width: 10.0,
                                    ),
                                    colorText("${data.totalBookmarks}", context)
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 2,
                              runSpacing: 0,
                              children: [
                                if (data.illustAIType == 2)
                                  Text("${I18n.of(context).ai_generated}",
                                      style: FluentTheme.of(context)
                                          .typography
                                          .caption!
                                          .copyWith(
                                              color: FluentTheme.of(context)
                                                  .accentColor)),
                                for (var f in data.tags) buildRow(context, f)
                              ],
                            ),
                          ),
                        ),
                        SliverToBoxAdapter(
                          child: Card(
                            child: Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: SelectableHtml(
                                data: data.caption.isEmpty ? "~" : data.caption,
                              ),
                            ),
                          ),
                        ),
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: HyperlinkButton(
                              child: Text(
                                I18n.of(context).view_comment,
                                textAlign: TextAlign.center,
                                style: FluentTheme.of(context).typography.body!,
                              ),
                              onPressed: () {
                                Leader.push(context, CommentPage(id: data.id),
                                    icon: Icon(FluentIcons.comment),
                                    title: Text(I18n.of(context).view_comment));
                              },
                            ),
                          ),
                        ),
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Text(I18n.of(context).about_picture),
                          ),
                        ),
                        _buildRecom()
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  SliverGrid _buildRecom() {
    return SliverGrid(
        delegate: SliverChildBuilderDelegate((BuildContext context, int index) {
          var list = _aboutStore.illusts
              .map((element) => IllustStore(element.id, element))
              .toList();
          return IconButton(
            onPressed: () {
              Leader.push(
                  context,
                  PictureListPage(
                    iStores: list,
                    lightingStore: null,
                    store: list[index],
                  ));
            },
            onLongPress: () {
              saveStore.saveImage(_aboutStore.illusts[index]);
            },
            icon: PixivImage(
              _aboutStore.illusts[index].imageUrls.squareMedium,
              enableMemoryCache: false,
            ),
          );
        }, childCount: _aboutStore.illusts.length),
        gridDelegate:
            SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3));
  }

  List<Widget> _buildPhotoList(Illusts data, bool centerType, double height) {
    return [
      if (data.type == "ugoira")
        SliverToBoxAdapter(
          child: NullHero(
            tag: widget.heroString,
            child: UgoiraLoader(
              id: widget.id,
              illusts: data,
            ),
          ),
        ),
      if (data.type != "ugoira")
        data.pageCount == 1
            ? (centerType
                ? SliverFillRemaining(
                    child: _buildPicture(data, height),
                  )
                : SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                    return _buildPicture(data, height);
                  }, childCount: 1)))
            : SliverList(
                delegate: SliverChildBuilderDelegate(
                    (BuildContext context, int index) {
                return IconButton(
                    onLongPress: () {
                      _pressSave(data, index);
                    },
                    onPressed: () {
                      Leader.push(
                          context,
                          PhotoZoomPage(
                            index: index,
                            illusts: data,
                          ));
                    },
                    icon: _buildIllustsItem(index, data, height));
              }, childCount: data.metaPages.length)),
    ];
  }

  Widget _buildPicture(Illusts data, double height) {
    return Center(child: Builder(
      builder: (BuildContext context) {
        String url = userSetting.pictureQuality == 1
            ? data.imageUrls.large
            : data.imageUrls.medium;
        if (data.type == "manga") {
          if (userSetting.mangaQuality == 0)
            url = data.imageUrls.medium;
          else if (userSetting.mangaQuality == 1)
            url = data.imageUrls.large;
          else
            url = data.metaSinglePage!.originalImageUrl!;
        }
        Widget placeWidget = Container(height: height);
        return IconButton(
          onLongPress: () {
            _pressSave(data, 0);
          },
          onPressed: () {
            Leader.push(
              context,
              PhotoZoomPage(
                index: 0,
                illusts: data,
              ),
              icon: Icon(FluentIcons.picture),
              title: Text(I18n.of(context).illust_id + ': ${data.id}'),
            );
          },
          icon: NullHero(
            tag: widget.heroString,
            child: PixivImage(
              url,
              fade: false,
              width: MediaQuery.of(context).size.width,
              placeWidget: (url != data.imageUrls.medium)
                  ? PixivImage(
                      data.imageUrls.medium,
                      width: MediaQuery.of(context).size.width,
                      placeWidget: placeWidget,
                      fade: false,
                    )
                  : placeWidget,
            ),
          ),
        );
      },
    ));
  }

  Center _buildErrorContent(BuildContext context) {
    return Center(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(':(', style: FluentTheme.of(context).typography.title),
          ),
          Text(
            '${_illustStore.errorMessage}',
            maxLines: 5,
          ),
          FilledButton(
            onPressed: () {
              _illustStore.fetch();
            },
            child: Text(I18n.of(context).refresh),
          )
        ],
      ),
    );
  }

  Widget _buildIllustsItem(int index, Illusts illust, double height) {
    if (illust.type == "manga") {
      String url;
      if (userSetting.mangaQuality == 0)
        url = illust.metaPages[index].imageUrls!.medium;
      else if (userSetting.mangaQuality == 1)
        url = illust.metaPages[index].imageUrls!.large;
      else
        url = illust.metaPages[index].imageUrls!.original;
      if (index == 0)
        return NullHero(
          child: PixivImage(
            url,
            placeWidget: PixivImage(
              illust.metaPages[index].imageUrls!.medium,
              width: MediaQuery.of(context).size.width,
              fade: false,
            ),
            width: MediaQuery.of(context).size.width,
            fade: false,
          ),
          tag: widget.heroString,
        );
      return PixivImage(
        url,
        fade: false,
        width: MediaQuery.of(context).size.width,
        placeWidget: Container(
          height: height,
          child: Center(
            child:
                Text('$index', style: FluentTheme.of(context).typography.title),
          ),
        ),
      );
    }
    return index == 0
        ? (userSetting.pictureQuality == 1
            ? NullHero(
                child: PixivImage(
                  illust.metaPages[index].imageUrls!.large,
                  placeWidget: PixivImage(
                    illust.metaPages[index].imageUrls!.medium,
                    fade: false,
                  ),
                  fade: false,
                ),
                tag: widget.heroString,
              )
            : NullHero(
                child: PixivImage(
                  illust.metaPages[index].imageUrls!.medium,
                  fade: false,
                ),
                tag: widget.heroString,
              ))
        : PixivImage(
            userSetting.pictureQuality == 0
                ? illust.metaPages[index].imageUrls!.medium
                : illust.metaPages[index].imageUrls!.large,
            fade: false,
            placeWidget: Container(
              height: 150,
              child: Center(
                child: Text('$index',
                    style: FluentTheme.of(context).typography.title),
              ),
            ),
          );
  }

  Future _longPressTag(BuildContext context, Tags f) async {
    switch (await showDialog(
        context: context,
        builder: (BuildContext context) {
          return ContentDialog(
            title: Text(f.name),
            actions: <Widget>[
              Button(
                onPressed: () {
                  Navigator.pop(context, 0);
                },
                child: Text(I18n.of(context).ban),
              ),
              Button(
                onPressed: () {
                  Navigator.pop(context, 1);
                },
                child: Text(I18n.of(context).bookmark),
              ),
              Button(
                onPressed: () {
                  Navigator.pop(context, 2);
                },
                child: Text(I18n.of(context).copy),
              ),
            ],
          );
        })) {
      case 0:
        {
          muteStore.insertBanTag(BanTagPersist(
              name: f.name, translateName: f.translatedName ?? ""));
        }
        break;
      case 1:
        {
          bookTagStore.bookTag(f.name);
        }
        break;
      case 2:
        {
          await Clipboard.setData(ClipboardData(text: f.name));
          showSnackbar(
              context,
              Snackbar(
                content: Text(I18n.of(context).copied_to_clipboard),
              ));
        }
    }
  }

  Widget buildRow(BuildContext context, Tags f) {
    return GestureDetector(
      onLongPress: () async {
        await _longPressTag(context, f);
      },
      onTap: () {
        Leader.push(
          context,
          ResultPage(
            word: f.name,
            translatedName: f.translatedName ?? "",
          ),
          icon: Icon(FluentIcons.show_results),
          title: Text(I18n.of(context).tag + ' #${f.name}'),
        );
      },
      child: RichText(
          textAlign: TextAlign.center,
          text: TextSpan(
              text: "#${f.name}",
              children: [
                TextSpan(
                  text: " ",
                  style: FluentTheme.of(context).typography.caption,
                ),
                TextSpan(
                    text: "${f.translatedName ?? "~"}",
                    style: FluentTheme.of(context).typography.caption)
              ],
              style: FluentTheme.of(context)
                  .typography
                  .caption!
                  .copyWith(color: FluentTheme.of(context).accentColor))),
    );
  }

  Widget _buildNameAvatar(BuildContext context, Illusts illust) {
    if (userStore == null)
      userStore = UserStore(illust.user.id, user: illust.user);
    return Observer(builder: (_) {
      Future.delayed(Duration(seconds: 2), () {
        _loadAbout();
      });
      return Row(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Padding(
              child: GestureDetector(
                onLongPress: () {
                  userStore!.follow();
                },
                child: Container(
                  height: 70,
                  width: 70,
                  child: Stack(
                    children: <Widget>[
                      Center(
                        child: SizedBox(
                          height: 70,
                          width: 70,
                          child: Container(
                            decoration: illust != null
                                ? BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: userStore!.isFollow
                                        ? Colors.yellow
                                        : FluentTheme.of(context).accentColor,
                                  )
                                : BoxDecoration(),
                          ),
                        ),
                      ),
                      Center(
                        child: Hero(
                          tag: illust.user.profileImageUrls.medium +
                              this.hashCode.toString(),
                          child: PainterAvatar(
                            url: illust.user.profileImageUrls.medium,
                            id: illust.user.id,
                            onTap: () async {
                              await Leader.push(
                                context,
                                UsersPage(
                                  id: illust.user.id,
                                  userStore: userStore,
                                  heroTag: this.hashCode.toString(),
                                ),
                                icon: Icon(FluentIcons.account_browser),
                                title: Text(I18n.of(context).painter_id +
                                    '${illust.user.id}'),
                              );
                              _illustStore.illusts!.user.isFollowed =
                                  userStore!.isFollow;
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              padding: EdgeInsets.all(8.0)),
          Expanded(
            child: Padding(
              padding: EdgeInsets.all(8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.start,
                children: <Widget>[
                  Text(
                    illust.title,
                    style:
                        TextStyle(color: FluentTheme.of(context).accentColor),
                  ),
                  Container(
                    height: 4.0,
                  ),
                  Hero(
                    tag: illust.user.name + this.hashCode.toString(),
                    child: Text(
                      illust.user.name,
                      style: FluentTheme.of(context).typography.body,
                    ),
                  ),
                  Text(
                    illust.createDate.toShortTime(),
                    style: FluentTheme.of(context).typography.caption,
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    });
  }

  Future<void> _pressSave(Illusts illust, int index) async {
    showBottomSheet(
        context: context,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(16),
          ),
        ),
        builder: (c1) {
          return Container(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                illust.metaPages.isNotEmpty
                    ? ListTile(
                        title: Text(I18n.of(context).muti_choice_save),
                        leading: Icon(
                          FluentIcons.save,
                        ),
                        onPressed: () async {
                          Navigator.of(context).pop();
                          _showMutiChoiceDialog(illust, context);
                        },
                      )
                    : Container(),
                ListTile(
                  leading: Icon(FluentIcons.save),
                  onPressed: () async {
                    Navigator.of(context).pop();
                    saveStore.saveImage(illust, index: index);
                  },
                  // onLongPress: () async {
                  //   Navigator.of(context).pop();
                  //   saveStore.saveImage(illust, index: index);
                  // },
                  title: Text(I18n.of(context).save),
                ),
                ListTile(
                  leading: Icon(FluentIcons.cancel),
                  onPressed: () => Navigator.of(context).pop(),
                  title: Text(I18n.of(context).cancel),
                ),
                Container(
                  height: MediaQuery.of(c1).padding.bottom,
                )
              ],
            ),
          );
        });
  }

  Future _showMutiChoiceDialog(Illusts illust, BuildContext context) async {
    List<bool> indexs = [];
    bool allOn = false;
    for (int i = 0; i < illust.metaPages.length; i++) {
      indexs.add(false);
    }
    final result = await showBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(16.0))),
        builder: (context) {
          return StatefulBuilder(builder: (context, setDialogState) {
            return SafeArea(
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.8,
                child: Column(
                  children: [
                    Container(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Text(illust.title),
                      ),
                    ),
                    Expanded(
                      child: GridView.builder(
                        itemBuilder: (context, index) {
                          final data = illust.metaPages[index];
                          return Container(
                              child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: IconButton(
                              onPressed: () {
                                setDialogState(() {
                                  indexs[index] = !indexs[index];
                                });
                              },
                              onLongPress: () {
                                Leader.push(
                                  context,
                                  PhotoZoomPage(index: index, illusts: illust),
                                  icon: Icon(FluentIcons.picture),
                                  title: Text(I18n.of(context).illust_id +
                                      '${illust.id}'),
                                );
                              },
                              icon: Stack(
                                children: [
                                  PixivImage(
                                    data.imageUrls!.squareMedium,
                                    placeWidget: Container(
                                      child: Center(
                                        child: Text(index.toString()),
                                      ),
                                    ),
                                  ),
                                  Align(
                                      alignment: Alignment.bottomRight,
                                      child: Visibility(
                                          visible: indexs[index],
                                          child: Padding(
                                            padding: const EdgeInsets.all(4.0),
                                            child: Icon(
                                              FluentIcons.checkbox,
                                              color: Colors.green,
                                            ),
                                          ))),
                                ],
                              ),
                            ),
                          ));
                        },
                        itemCount: illust.metaPages.length,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3),
                      ),
                    ),
                    ListTile(
                      leading: Icon(!allOn
                          ? FluentIcons.checkbox_fill
                          : FluentIcons.checkbox),
                      title: Text(I18n.of(context).all),
                      onPressed: () {
                        allOn = !allOn;
                        for (var i = 0; i < indexs.length; i++) {
                          indexs[i] = allOn;
                        }
                        setDialogState(() {});
                      },
                    ),
                    ListTile(
                      leading: Icon(FluentIcons.save),
                      title: Text(I18n.of(context).save),
                      onPressed: () {
                        Navigator.of(context).pop("OK");
                      },
                    ),
                  ],
                ),
              ),
            );
          });
        });
    switch (result) {
      case "OK":
        {
          saveStore.saveChoiceImage(illust, indexs);
        }
    }
  }

  Future buildshowBottomSheet(BuildContext context, Illusts illusts) {
    return showBottomSheet(
        isScrollControlled: true,
        context: context,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(16),
          ),
        ),
        builder: (_) {
          return Container(
            decoration: BoxDecoration(
                borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(8.0),
                    topRight: Radius.circular(8.0))),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: <Widget>[
                      _buildNameAvatar(context, illusts),
                      if (illusts.metaPages.isNotEmpty)
                        ListTile(
                          title: Text(I18n.of(context).muti_choice_save),
                          leading: Icon(
                            FluentIcons.save,
                          ),
                          onPressed: () async {
                            Navigator.of(context).pop();
                            _showMutiChoiceDialog(illusts, context);
                          },
                        ),
                      ListTile(
                        title: Text(I18n.of(context).copymessage),
                        leading: Icon(
                          FluentIcons.library,
                        ),
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(
                              text:
                                  'title:${illusts.title}\npainter:${illusts.user.name}\nillust id:${widget.id}'));
                          BotToast.showText(
                              text: I18n.of(context).copied_to_clipboard);
                          Navigator.of(context).pop();
                        },
                      ),
                      ListTile(
                        title: Text(I18n.of(context).share),
                        leading: Icon(
                          FluentIcons.share,
                        ),
                        onPressed: () {
                          Navigator.of(context).pop();
                          Share.share(
                              "https://www.pixiv.net/artworks/${widget.id}");
                        },
                      ),
                      ListTile(
                        leading: Icon(
                          FluentIcons.link,
                        ),
                        title: Text(I18n.of(context).link),
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(
                              text:
                                  "https://www.pixiv.net/artworks/${widget.id}"));
                          BotToast.showText(
                              text: I18n.of(context).copied_to_clipboard);
                          Navigator.of(context).pop();
                        },
                      ),
                      ListTile(
                        title: Text(I18n.of(context).ban),
                        leading: Icon(FluentIcons.brightness),
                        onPressed: () {
                          muteStore.insertBanIllusts(BanIllustIdPersist(
                              illustId: widget.id.toString(),
                              name: illusts.title));
                          Navigator.pop(context);
                        },
                      ),
                      ListTile(
                        title: Text(I18n.of(context).report),
                        leading: Icon(FluentIcons.report_document),
                        onPressed: () async {
                          await showDialog(
                              context: context,
                              builder: (context) {
                                return ContentDialog(
                                  title: Text(I18n.of(context).report),
                                  content:
                                      Text(I18n.of(context).report_message),
                                  actions: <Widget>[
                                    HyperlinkButton(
                                      child: Text(I18n.of(context).cancel),
                                      onPressed: () {
                                        Navigator.of(context).pop("CANCEL");
                                      },
                                    ),
                                    HyperlinkButton(
                                      child: Text(I18n.of(context).ok),
                                      onPressed: () {
                                        Navigator.of(context).pop("OK");
                                      },
                                    ),
                                  ],
                                );
                              });
                        },
                      )
                    ],
                  ),
                  Container(
                    height: MediaQuery.of(context).padding.bottom,
                  )
                ],
              ),
            ),
          );
        });
  }

  Future<void> _showBookMarkTag() async {
    final result =
        await Leader.pushWithScaffold(context, TagForIllustPage(id: widget.id));
    if (result is Map) {
      LPrinter.d(result);
      String restrict = result['restrict'];
      List<String>? tags = result['tags'];
      _illustStore.star(restrict: restrict, tags: tags, force: true);
    }
  }

  @override
  bool get wantKeepAlive => false;
}