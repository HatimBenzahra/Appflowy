import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/base/selectable_svg_widget.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/plugins.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';

import 'slash_menu_item_builder.dart';

final _keywords = [
  'excalidraw',
  'drawing',
  'diagram',
  'sketch',
  'whiteboard',
];

SelectionMenuItem excalidrawSlashMenuItem = SelectionMenuItem(
  getName: () => 'Excalidraw',
  keywords: _keywords,
  handler: (editorState, _, __) async => editorState.insertExcalidrawBlock(),
  nameBuilder: slashMenuItemNameBuilder,
  icon: (_, isSelected, style) => SelectableSvgWidget(
    data: FlowySvgs.slash_menu_icon_file_s,
    isSelected: isSelected,
    style: style,
  ),
);

extension on EditorState {
  Future<void> insertExcalidrawBlock() async {
    final excalidrawKey = GlobalKey<ExcalidrawBlockComponentWidgetState>();
    await insertEmptyExcalidrawBlock(excalidrawKey);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      excalidrawKey.currentState?.showEditingDialog();
    });
  }
}
