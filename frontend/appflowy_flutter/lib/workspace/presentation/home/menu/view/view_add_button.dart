import 'dart:convert';

import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/document.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/import/import_panel.dart';
import 'package:appflowy/workspace/presentation/widgets/pop_up_action.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/file_picker/file_picker_service.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';

class ViewAddButton extends StatelessWidget {
  const ViewAddButton({
    super.key,
    required this.parentViewId,
    required this.onEditing,
    required this.onSelected,
    this.isHovered = false,
  });

  final String parentViewId;
  final void Function(bool value) onEditing;
  final Function(
    PluginBuilder,
    String? name,
    List<int>? initialDataBytes,
    bool openAfterCreated,
    bool createNewView,
  ) onSelected;
  final bool isHovered;

  List<PopoverAction> get _actions {
    return [
      // document, grid, kanban, calendar
      ...pluginBuilders().map(
        (pluginBuilder) => ViewAddButtonActionWrapper(
          pluginBuilder: pluginBuilder,
        ),
      ),
      // import from ...
      ...getIt<PluginSandbox>().builders.whereType<DocumentPluginBuilder>().map(
            (pluginBuilder) => ViewImportActionWrapper(
              pluginBuilder: pluginBuilder,
            ),
          ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return PopoverActionList<PopoverAction>(
      direction: PopoverDirection.bottomWithLeftAligned,
      actions: _actions,
      offset: const Offset(0, 8),
      constraints: const BoxConstraints(
        minWidth: 200,
      ),
      buildChild: (popover) {
        return FlowyIconButton(
          width: 24,
          icon: FlowySvg(
            FlowySvgs.view_item_add_s,
            color: isHovered ? Theme.of(context).colorScheme.onSurface : null,
          ),
          onPressed: () {
            onEditing(true);
            popover.show();
          },
        );
      },
      onSelected: (action, popover) {
        onEditing(false);
        if (action is ViewAddButtonActionWrapper) {
          _showViewAddButtonActions(context, action);
        } else if (action is ViewImportActionWrapper) {
          _showViewImportAction(context, action);
        }
        popover.close();
      },
      onClosed: () {
        onEditing(false);
      },
    );
  }

  void _showViewAddButtonActions(
    BuildContext context,
    ViewAddButtonActionWrapper action,
  ) {
    final pluginType = action.pluginBuilder.pluginType;

    // File-based plugins: show file picker FIRST, then create views
    if (pluginType == PluginType.pdfViewer ||
        pluginType == PluginType.imageViewer ||
        pluginType == PluginType.excalidraw) {
      _handleFileBasedPlugin(context, action);
      return;
    }

    // Standard plugins: delegate to the parent's onSelected handler
    onSelected(action.pluginBuilder, null, null, true, true);
  }

  Future<void> _handleFileBasedPlugin(
    BuildContext context,
    ViewAddButtonActionWrapper action,
  ) async {
    final pluginType = action.pluginBuilder.pluginType;

    // Determine file picker configuration based on plugin type
    late final FileType fileType;
    late final List<String>? allowedExtensions;
    late final String customViewType;
    late final String filePathKey;
    late final ViewLayoutPB layoutType;

    switch (pluginType) {
      case PluginType.pdfViewer:
        fileType = FileType.custom;
        allowedExtensions = ['pdf'];
        customViewType = 'pdf_viewer';
        filePathKey = 'pdf_path';
        layoutType = ViewLayoutPB.PdfViewer;
        break;
      case PluginType.imageViewer:
        fileType = FileType.custom;
        allowedExtensions = ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'];
        customViewType = 'image_viewer';
        filePathKey = 'image_path';
        layoutType = ViewLayoutPB.ImageViewer;
        break;
      case PluginType.excalidraw:
        fileType = FileType.custom;
        allowedExtensions = ['excalidraw', 'json'];
        customViewType = 'excalidraw';
        filePathKey = 'excalidraw_file_path';
        layoutType = ViewLayoutPB.Excalidraw;
        break;
      default:
        return;
    }

    // Show file picker IMMEDIATELY — no view created yet
    final result = await getIt<FilePickerService>().pickFiles(
      dialogTitle: '',
      type: fileType,
      allowedExtensions: allowedExtensions,
      allowMultiple: true,
    );

    // User cancelled → do nothing (no blank page created)
    if (result == null || result.files.isEmpty) {
      return;
    }

    final files = result.files
        .where((file) => file.path != null && file.path!.isNotEmpty)
        .toList();
    if (files.isEmpty) return;

    // Create one view per selected file, with extra set atomically
    for (int i = 0; i < files.length; i++) {
      final file = files[i];
      final filePath = file.path!;
      final fileName = _fileNameWithoutExtension(file.name);

      // Build the extra JSON with both custom_view_type and file path
      final extraJson = jsonEncode({
        'custom_view_type': customViewType,
        filePathKey: filePath,
      });

      await ViewBackendService.createView(
        layoutType: layoutType,
        parentViewId: parentViewId,
        name: fileName,
        openAfterCreate: i == 0, // Only open the first file
        extra: extraJson,
      );
    }
  }

  String _fileNameWithoutExtension(String fileName) {
    final dotIndex = fileName.lastIndexOf('.');
    if (dotIndex <= 0) return fileName;
    return fileName.substring(0, dotIndex);
  }

  void _showViewImportAction(
    BuildContext context,
    ViewImportActionWrapper action,
  ) {
    showImportPanel(
      parentViewId,
      context,
      (type, name, initialDataBytes) {
        onSelected(action.pluginBuilder, null, null, true, false);
      },
    );
  }
}

class ViewAddButtonActionWrapper extends ActionCell {
  ViewAddButtonActionWrapper({
    required this.pluginBuilder,
  });

  final PluginBuilder pluginBuilder;

  @override
  Widget? leftIcon(Color iconColor) => FlowySvg(
        pluginBuilder.icon,
        size: const Size.square(16),
      );

  @override
  String get name => pluginBuilder.menuName;

  PluginType get pluginType => pluginBuilder.pluginType;
}

class ViewImportActionWrapper extends ActionCell {
  ViewImportActionWrapper({
    required this.pluginBuilder,
  });

  final DocumentPluginBuilder pluginBuilder;

  @override
  Widget? leftIcon(Color iconColor) => const FlowySvg(FlowySvgs.icon_import_s);

  @override
  String get name => LocaleKeys.moreAction_import.tr();
}
