library;

import 'package:appflowy/features/page_access_level/logic/page_access_level_bloc.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/plugins/image_viewer/image_viewer_page.dart';
import 'package:appflowy/plugins/util.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/presentation/home/home_stack.dart';
import 'package:appflowy/workspace/presentation/widgets/tab_bar_item.dart';
import 'package:appflowy/workspace/presentation/widgets/view_title_bar.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class ImageViewerPluginBuilder extends PluginBuilder {
  @override
  Plugin build(dynamic data) {
    if (data is ViewPB) {
      return ImageViewerPlugin(view: data);
    }

    throw FlowyPluginException.invalidData;
  }

  @override
  String get menuName => 'Image';

  @override
  FlowySvgData get icon => FlowySvgs.image_s;

  @override
  PluginType get pluginType => PluginType.imageViewer;

  @override
  ViewLayoutPB get layoutType => ViewLayoutPB.ImageViewer;
}

class ImageViewerPluginConfig implements PluginConfig {
  @override
  bool get creatable => true;
}

class ImageViewerPlugin extends Plugin {
  ImageViewerPlugin({
    required ViewPB view,
  }) : notifier = ViewPluginNotifier(view: view);

  late final PageAccessLevelBloc _pageAccessLevelBloc;

  @override
  final ViewPluginNotifier notifier;

  @override
  PluginWidgetBuilder get widgetBuilder => ImageViewerPluginWidgetBuilder(
        notifier: notifier,
        pageAccessLevelBloc: _pageAccessLevelBloc,
      );

  @override
  PluginId get id => notifier.view.id;

  @override
  PluginType get pluginType => PluginType.imageViewer;

  @override
  void init() {
    _pageAccessLevelBloc = PageAccessLevelBloc(view: notifier.view)
      ..add(const PageAccessLevelEvent.initial());
  }

  @override
  void dispose() {
    _pageAccessLevelBloc.close();
    notifier.dispose();
  }
}

class ImageViewerPluginWidgetBuilder extends PluginWidgetBuilder
    with NavigationItem {
  ImageViewerPluginWidgetBuilder({
    required this.notifier,
    required this.pageAccessLevelBloc,
  });

  final ViewPluginNotifier notifier;
  final PageAccessLevelBloc pageAccessLevelBloc;
  int? deletedViewIndex;

  @override
  String? get viewName => notifier.view.nameOrDefault;

  @override
  Widget get leftBarItem {
    return BlocProvider.value(
      value: pageAccessLevelBloc,
      child: ViewTitleBar(
        key: ValueKey(notifier.view.id),
        view: notifier.view,
      ),
    );
  }

  @override
  Widget tabBarItem(String pluginId, [bool shortForm = false]) =>
      ViewTabBarItem(view: notifier.view, shortForm: shortForm);

  @override
  Widget buildWidget({
    required PluginContext context,
    required bool shrinkWrap,
    Map<String, dynamic>? data,
  }) {
    notifier.isDeleted.addListener(() {
      final deletedView = notifier.isDeleted.value;
      if (deletedView != null && deletedView.hasIndex()) {
        deletedViewIndex = deletedView.index;
      }
    });

    return ImageViewerPage(
      key: ValueKey(notifier.view.id),
      view: notifier.view,
    );
  }

  @override
  List<NavigationItem> get navigationItems => [this];

  @override
  EdgeInsets get contentPadding => EdgeInsets.zero;
}
