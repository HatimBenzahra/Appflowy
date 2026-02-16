import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/actions/mobile_block_action_buttons.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/block_menu/block_menu_button.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/excalidraw/excalidraw_editor_dialog.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flowy_infra_ui/style_widget/hover.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:universal_platform/universal_platform.dart';

class ExcalidrawBlockKeys {
  const ExcalidrawBlockKeys._();

  static const String type = 'excalidraw';
  static const String data = 'data';
  static const String width = 'width';
  static const String height = 'height';

  /// The GlobalKey of the ExcalidrawBlockComponentWidgetState.
  ///
  /// **Note: This value is used in extraInfos of the Node, not in the attributes.**
  static const String globalKey = 'global_key';
}

Node excalidrawNode({
  String data = '{}',
  double width = double.infinity,
  double height = 400,
}) {
  final attributes = {
    ExcalidrawBlockKeys.data: data,
    ExcalidrawBlockKeys.width: width,
    ExcalidrawBlockKeys.height: height,
  };

  return Node(
    type: ExcalidrawBlockKeys.type,
    attributes: attributes,
  );
}

class ExcalidrawBlockComponentBuilder extends BlockComponentBuilder {
  ExcalidrawBlockComponentBuilder({
    super.configuration,
  });

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    final extraInfos = node.extraInfos;
    final key = extraInfos?[ExcalidrawBlockKeys.globalKey] as GlobalKey?;

    return ExcalidrawBlockComponentWidget(
      key: key ?? node.key,
      node: node,
      configuration: configuration,
      showActions: showActions(node),
      actionBuilder: (context, state) => actionBuilder(
        blockComponentContext,
        state,
      ),
      actionTrailingBuilder: (context, state) => actionTrailingBuilder(
        blockComponentContext,
        state,
      ),
    );
  }

  @override
  BlockComponentValidate get validate => (node) =>
      node.children.isEmpty &&
      node.attributes[ExcalidrawBlockKeys.data] is String &&
      node.attributes[ExcalidrawBlockKeys.width] is num &&
      node.attributes[ExcalidrawBlockKeys.height] is num;
}

class ExcalidrawBlockComponentWidget extends BlockComponentStatefulWidget {
  const ExcalidrawBlockComponentWidget({
    super.key,
    required super.node,
    super.showActions,
    super.actionBuilder,
    super.actionTrailingBuilder,
    super.configuration = const BlockComponentConfiguration(),
  });

  @override
  State<ExcalidrawBlockComponentWidget> createState() =>
      ExcalidrawBlockComponentWidgetState();
}

class ExcalidrawBlockComponentWidgetState
    extends State<ExcalidrawBlockComponentWidget>
    with BlockComponentConfigurable {
  @override
  BlockComponentConfiguration get configuration => widget.configuration;

  @override
  Node get node => widget.node;

  String get data =>
      widget.node.attributes[ExcalidrawBlockKeys.data] as String? ?? '{}';

  double get width {
    final value = widget.node.attributes[ExcalidrawBlockKeys.width];
    if (value is num) {
      return value.toDouble();
    }
    return double.infinity;
  }

  double get height {
    final value = widget.node.attributes[ExcalidrawBlockKeys.height];
    if (value is num) {
      return value.toDouble();
    }
    return 400;
  }

  late final editorState = context.read<EditorState>();
  final ValueNotifier<bool> isHover = ValueNotifier(false);

  @override
  void dispose() {
    isHover.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onHover: (value) => isHover.value = value,
      onTap: showEditingDialog,
      child: _build(context),
    );
  }

  Widget _build(BuildContext context) {
    Widget child = Container(
      width: width,
      constraints: BoxConstraints(minHeight: height),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: FlowyHover(
        style: HoverStyle(
          borderRadius: BorderRadius.circular(4),
        ),
        child: _isDataEmpty(data)
            ? _buildPlaceholderWidget(context)
            : _buildPreviewWidget(context),
      ),
    );

    if (widget.showActions && widget.actionBuilder != null) {
      child = BlockComponentActionWrapper(
        node: node,
        actionBuilder: widget.actionBuilder!,
        actionTrailingBuilder: widget.actionTrailingBuilder,
        child: child,
      );
    }

    if (UniversalPlatform.isMobile) {
      child = MobileBlockActionButtons(
        node: node,
        editorState: editorState,
        child: child,
      );
    }

    child = Padding(
      padding: padding,
      child: child,
    );

    if (UniversalPlatform.isDesktopOrWeb) {
      child = Stack(
        children: [
          child,
          Positioned(
            right: 6,
            top: 12,
            child: ValueListenableBuilder<bool>(
              valueListenable: isHover,
              builder: (_, value, __) =>
                  value ? _buildDeleteButton(context) : const SizedBox.shrink(),
            ),
          ),
        ],
      );
    }

    return child;
  }

  Widget _buildPlaceholderWidget(BuildContext context) {
    return SizedBox(
      height: 52,
      child: Row(
        children: [
          const HSpace(10),
          FlowySvg(
            FlowySvgs.slash_menu_icon_file_s,
            color: Theme.of(context).hintColor,
            size: const Size.square(24),
          ),
          const HSpace(10),
          FlowyText(
            'Click to create a drawing',
            color: Theme.of(context).hintColor,
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewWidget(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FlowyText(
              'Excalidraw Drawing',
              color: Theme.of(context).hintColor,
            ),
            const HSpace(8),
            Icon(
              Icons.edit_outlined,
              size: 16,
              color: Theme.of(context).hintColor,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeleteButton(BuildContext context) {
    return MenuBlockButton(
      tooltip: MaterialLocalizations.of(context).deleteButtonTooltip,
      iconData: FlowySvgs.trash_s,
      onTap: () {
        final transaction = editorState.transaction..deleteNode(widget.node);
        editorState.apply(transaction);
      },
    );
  }

  bool _isDataEmpty(String rawData) {
    final trimmed = rawData.trim();
    return trimmed.isEmpty || trimmed == '{}' || trimmed == 'null';
  }

  Future<void> showEditingDialog() async {
    final updatedData = await showExcalidrawEditorDialog(
      context,
      initialData: data,
    );
    if (updatedData == null || updatedData == data) {
      return;
    }
    final transaction = editorState.transaction
      ..updateNode(
        widget.node,
        {
          ExcalidrawBlockKeys.data: updatedData,
          ExcalidrawBlockKeys.width: width,
          ExcalidrawBlockKeys.height: height,
        },
      );
    await editorState.apply(transaction);
  }
}

extension InsertExcalidrawBlock on EditorState {
  Future<void> insertEmptyExcalidrawBlock(GlobalKey key) async {
    final selection = this.selection;
    if (selection == null || !selection.isCollapsed) {
      return;
    }

    final path = selection.end.path;
    final node = getNodeAtPath(path);
    final delta = node?.delta;
    if (node == null || delta == null) {
      return;
    }

    final excalidraw = excalidrawNode()
      ..extraInfos = {ExcalidrawBlockKeys.globalKey: key};
    final transaction = this.transaction;

    if (delta.isEmpty && node.type == ParagraphBlockKeys.type) {
      final insertedPath = path;
      transaction.insertNode(insertedPath, excalidraw);
      transaction.deleteNode(node);
    } else {
      final insertedPath = path.next;
      transaction.insertNode(insertedPath, excalidraw);
    }

    return apply(transaction);
  }
}
