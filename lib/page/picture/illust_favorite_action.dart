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
import 'package:flutter/material.dart';
import 'package:pixez/i18n.dart';
import 'package:pixez/main.dart';
import 'package:pixez/page/picture/illust_store.dart';
import 'package:pixez/page/user/user_store.dart';

/// 收藏/取消收藏当前插画（与详情页收藏悬浮钮逻辑一致）。
/// 供详情页收藏 FAB 与鸿蒙 HDS 迷你胶囊共用。
Future<void> toggleIllustFavorite(
  BuildContext context,
  IllustStore store, {
  UserStore? userStore,
}) async {
  if (userSetting.saveAfterStar && (store.state == 0)) {
    saveStore.saveImage(store.illusts!);
  }
  // TODO: 添加配置项 开关和过滤器
  final List<String>? tags;
  if (userSetting.autoTagWhenStar) {
    final filters = [RegExp(r"\d+users入り")];
    tags = store.illusts!.tags
        .map((tag) => tag.name)
        .where((tag) => !filters.any((regex) => regex.hasMatch(tag)))
        .toList();
  } else {
    tags = null;
  }
  bool success = await store.star(
    restrict: userSetting.defaultPrivateLike ? "private" : "public",
    tags: tags,
  );
  if (success && userSetting.followAfterStar) {
    bool followSuccess = await store.followAfterStar();
    if (followSuccess) {
      userStore?.isFollow = true;
      BotToast.showText(
        text: "${store.illusts!.user.name} ${I18n.of(context).followed}",
      );
    }
  }
}
