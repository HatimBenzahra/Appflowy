import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/plugins/document/application/document_bloc.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/actions/mobile_block_action_buttons.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/block_menu/block_menu_button.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_util.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/presentation/home/toast.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/file_picker/file_picker_service.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flowy_infra_ui/style_widget/hover.dart';
import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';
import 'package:provider/provider.dart';
import 'package:universal_platform/universal_platform.dart';

class PdfViewerBlockKeys {
  const PdfViewerBlockKeys._();

  static const String type = 'pdf_viewer';
  static const String url = 'url';
  static const String uploadType = 'upload_type';
  static const String name = 'name';
  static const String height = 'height';

  /// The GlobalKey of the PdfViewerBlockComponentState.
  ///
  /// **Note: This value is used in extraInfos of the Node, not in the attributes.**
  static const String globalKey = 'global_key';
}

enum PdfViewerUploadType {
  local,
  cloud,
  network;

  int toIntValue() {
    switch (this) {
      case PdfViewerUploadType.local:
        return 0;
      case PdfViewerUploadType.cloud:
        return 1;
      case PdfViewerUploadType.network:
        return 2;
    }
  }

  static PdfViewerUploadType fromIntValue(int value) {
    switch (value) {
      case 0:
        return PdfViewerUploadType.local;
      case 1:
        return PdfViewerUploadType.cloud;
      case 2:
        return PdfViewerUploadType.network;
      default:
        return PdfViewerUploadType.local;
    }
  }
}

Node pdfViewerNode({
  String url = '',
  int uploadType = 0,
  String name = '',
  double height = 500,
}) {
  return Node(
    type: PdfViewerBlockKeys.type,
    attributes: {
      PdfViewerBlockKeys.url: url,
      PdfViewerBlockKeys.uploadType: uploadType,
      PdfViewerBlockKeys.name: name,
      PdfViewerBlockKeys.height: height,
    },
  );
}

class PdfViewerBlockComponentBuilder extends BlockComponentBuilder {
  PdfViewerBlockComponentBuilder({super.configuration});

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    final extraInfos = node.extraInfos;
    final key = extraInfos?[PdfViewerBlockKeys.globalKey] as GlobalKey?;

    return PdfViewerBlockComponentWidget(
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
      node.attributes[PdfViewerBlockKeys.url] is String &&
      node.attributes[PdfViewerBlockKeys.uploadType] is int &&
      node.attributes[PdfViewerBlockKeys.name] is String &&
      node.attributes[PdfViewerBlockKeys.height] is num;
}

class PdfViewerBlockComponentWidget extends BlockComponentStatefulWidget {
  const PdfViewerBlockComponentWidget({
    super.key,
    required super.node,
    super.showActions,
    super.actionBuilder,
    super.actionTrailingBuilder,
    super.configuration = const BlockComponentConfiguration(),
  });

  @override
  State<PdfViewerBlockComponentWidget> createState() =>
      PdfViewerBlockComponentState();
}

class PdfViewerBlockComponentState extends State<PdfViewerBlockComponentWidget>
    with BlockComponentConfigurable {
  static const double _defaultHeight = 500;
  static const double _minHeight = 240;
  static const double _minZoom = 1.0;
  static const double _maxZoom = 4.0;
  static const double _zoomStep = 0.25;

  @override
  BlockComponentConfiguration get configuration => widget.configuration;

  @override
  Node get node => widget.node;

  String get _url =>
      widget.node.attributes[PdfViewerBlockKeys.url] as String? ?? '';

  String get _name =>
      widget.node.attributes[PdfViewerBlockKeys.name] as String? ?? '';

  PdfViewerUploadType get _uploadType => PdfViewerUploadType.fromIntValue(
        widget.node.attributes[PdfViewerBlockKeys.uploadType] as int? ?? 0,
      );

  double get _height {
    final value = widget.node.attributes[PdfViewerBlockKeys.height];
    if (value is num) {
      return value.toDouble().clamp(_minHeight, double.infinity);
    }
    return _defaultHeight;
  }

  late final editorState = context.read<EditorState>();
  final ValueNotifier<bool> isHover = ValueNotifier(false);

  PdfControllerPinch? _pdfController;
  String? _loadedPdfPath;
  int _currentPage = 1;
  int _totalPages = 0;
  bool _isPicking = false;

  @override
  void initState() {
    super.initState();
    _updateControllerFromNode();
  }

  @override
  void didUpdateWidget(covariant PdfViewerBlockComponentWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateControllerFromNode();
  }

  @override
  void dispose() {
    isHover.dispose();
    _pdfController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onHover: (value) => isHover.value = value,
      onTap: _url.isEmpty ? pickPdfFile : null,
      child: _build(context),
    );
  }

  Widget _build(BuildContext context) {
    Widget child = Container(
      width: double.infinity,
      constraints: BoxConstraints(minHeight: _height),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: FlowyHover(
        style: HoverStyle(
          borderRadius: BorderRadius.circular(4),
        ),
        child: _url.isEmpty
            ? _buildPlaceholderWidget(context)
            : _buildPdfContent(context),
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
            'Add PDF Viewer',
            color: Theme.of(context).hintColor,
          ),
        ],
      ),
    );
  }

  Widget _buildPdfContent(BuildContext context) {
    if (_uploadType != PdfViewerUploadType.local || _pdfController == null) {
      return SizedBox(
        height: _height,
        child: Center(
          child: FlowyText(
            'PDF preview is available for local files only',
            color: Theme.of(context).hintColor,
          ),
        ),
      );
    }

    return SizedBox(
      height: _height,
      child: Column(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: PdfViewPinch(
                controller: _pdfController!,
                onPageChanged: (page) {
                  if (!mounted) {
                    return;
                  }
                  setState(() => _currentPage = page);
                },
                onDocumentLoaded: (document) {
                  if (!mounted) {
                    return;
                  }
                  setState(() {
                    _totalPages = document.pagesCount;
                    _currentPage = _pdfController?.page ?? 1;
                  });
                },
                onDocumentError: (_) {
                  if (!mounted) {
                    return;
                  }
                  setState(() {
                    _totalPages = 0;
                    _currentPage = 1;
                  });
                },
              ),
            ),
          ),
          _buildBottomBar(context),
        ],
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    final pageText = _totalPages > 0
        ? 'Page $_currentPage/$_totalPages'
        : 'Page $_currentPage';
    final zoomText = _pdfController == null
        ? '100%'
        : '${(_pdfController!.zoomRatio * 100).round()}%';

    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        children: [
          const HSpace(8),
          IconButton(
            tooltip: 'Previous page',
            icon: const Icon(Icons.navigate_before),
            onPressed: _currentPage > 1
                ? () => _pdfController?.previousPage(
                      duration: const Duration(milliseconds: 150),
                      curve: Curves.easeOut,
                    )
                : null,
          ),
          FlowyText(pageText),
          IconButton(
            tooltip: 'Next page',
            icon: const Icon(Icons.navigate_next),
            onPressed: _totalPages > 0 && _currentPage < _totalPages
                ? () => _pdfController?.nextPage(
                      duration: const Duration(milliseconds: 150),
                      curve: Curves.easeOut,
                    )
                : null,
          ),
          const Spacer(),
          IconButton(
            tooltip: 'Zoom out',
            icon: const Icon(Icons.remove),
            onPressed: _pdfController == null ? null : () => _zoomBy(-_zoomStep),
          ),
          FlowyText(zoomText),
          IconButton(
            tooltip: 'Zoom in',
            icon: const Icon(Icons.add),
            onPressed: _pdfController == null ? null : () => _zoomBy(_zoomStep),
          ),
          const HSpace(8),
        ],
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

  Future<void> pickPdfFile() async {
    if (_isPicking) {
      return;
    }
    _isPicking = true;

    final result = await getIt<FilePickerService>().pickFiles(
      dialogTitle: '',
      allowMultiple: false,
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
    );

    _isPicking = false;
    if (!mounted || result == null || result.files.isEmpty) {
      return;
    }

    final file = result.files.first;
    final path = file.xFile.path;
    if (path.isEmpty) {
      return;
    }

    final documentBloc = context.read<DocumentBloc>();
    final isLocalMode = documentBloc.isLocalMode;
    final uploadType =
        isLocalMode ? PdfViewerUploadType.local : PdfViewerUploadType.cloud;

    String? url;
    String? errorMessage;
    if (isLocalMode) {
      url = await saveFileToLocalStorage(path);
    } else {
      final result = await saveFileToCloudStorage(path, documentBloc.documentId);
      url = result.$1;
      errorMessage = result.$2;
    }

    if (!mounted) {
      return;
    }

    if (errorMessage != null) {
      showSnackBarMessage(context, errorMessage);
      return;
    }

    if (url == null) {
      return;
    }

    final transaction = editorState.transaction
      ..updateNode(widget.node, {
        PdfViewerBlockKeys.url: url,
        PdfViewerBlockKeys.uploadType: uploadType.toIntValue(),
        PdfViewerBlockKeys.name: file.name,
        PdfViewerBlockKeys.height: _height,
      });
    await editorState.apply(transaction);
  }

  void _updateControllerFromNode() {
    final path = _uploadType == PdfViewerUploadType.local && _url.isNotEmpty
        ? _url
        : null;

    if (_loadedPdfPath == path) {
      return;
    }

    final previous = _pdfController;

    _loadedPdfPath = path;
    if (path == null) {
      _pdfController = null;
      _currentPage = 1;
      _totalPages = 0;
      previous?.dispose();
      if (mounted) {
        setState(() {});
      }
      return;
    }

    _pdfController = PdfControllerPinch(
      document: PdfDocument.openFile(path),
      initialPage: 1,
    );
    _currentPage = 1;
    _totalPages = 0;
    previous?.dispose();

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _zoomBy(double delta) async {
    final controller = _pdfController;
    if (controller == null) {
      return;
    }

    final currentZoom = controller.zoomRatio;
    final targetZoom = (currentZoom + delta).clamp(_minZoom, _maxZoom);
    if (targetZoom == currentZoom) {
      return;
    }

    final factor = targetZoom / currentZoom;
    final destination = controller.value.clone()..scale(factor);
    await controller.goTo(
      destination: destination,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
    );

    if (mounted) {
      setState(() {});
    }
  }
}

extension InsertPdfViewerBlock on EditorState {
  Future<void> insertEmptyPdfViewerBlock(GlobalKey key) async {
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

    final pdfViewer = pdfViewerNode()..extraInfos = {'global_key': key};
    final transaction = this.transaction;

    if (delta.isEmpty && node.type == ParagraphBlockKeys.type) {
      final insertedPath = path;
      transaction.insertNode(insertedPath, pdfViewer);
      transaction.deleteNode(node);
    } else {
      final insertedPath = path.next;
      transaction.insertNode(insertedPath, pdfViewer);
    }

    return apply(transaction);
  }
}
