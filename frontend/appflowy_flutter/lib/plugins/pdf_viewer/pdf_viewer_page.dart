import 'dart:convert';
import 'dart:io';

import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flowy_infra/file_picker/file_picker_service.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

/// Displays a PDF file full-screen with text selection enabled.
///
/// The file path is read from the view's `extra` JSON (`pdf_path` key),
/// which is set atomically during view creation by [ViewAddButton].
/// A "swap" button allows replacing the PDF after initial creation.
class PdfViewerPage extends StatefulWidget {
  const PdfViewerPage({
    super.key,
    required this.view,
  });

  final ViewPB view;

  @override
  State<PdfViewerPage> createState() => _PdfViewerPageState();
}

class _PdfViewerPageState extends State<PdfViewerPage> {
  String? _pdfPath;

  @override
  void initState() {
    super.initState();
    _pdfPath = _readPdfPath();
  }

  String? _readPdfPath() {
    try {
      if (widget.view.extra.isNotEmpty) {
        final ext = jsonDecode(widget.view.extra) as Map<String, dynamic>;
        final path = ext['pdf_path'] as String?;
        if (path != null && path.isNotEmpty && File(path).existsSync()) {
          return path;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Let the user swap the PDF for this view.
  Future<void> _pickReplacementPdf() async {
    final result = await getIt<FilePickerService>().pickFiles(
      dialogTitle: '',
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      allowMultiple: false,
    );

    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final filePath = file.path;
    if (filePath == null || filePath.isEmpty) return;

    // Persist the new path in the view's extra
    Map<String, dynamic> ext = {};
    try {
      if (widget.view.extra.isNotEmpty) {
        ext = jsonDecode(widget.view.extra) as Map<String, dynamic>;
      }
    } catch (_) {}
    ext['pdf_path'] = filePath;

    await ViewBackendService.updateView(
      viewId: widget.view.id,
      extra: jsonEncode(ext),
    );

    if (!mounted) return;
    setState(() => _pdfPath = filePath);
  }

  @override
  Widget build(BuildContext context) {
    if (_pdfPath == null) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _pickReplacementPdf,
        child: Center(
          child: Text(
            'Click to select PDF',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.5),
                ),
          ),
        ),
      );
    }

    return Stack(
      children: [
        Positioned.fill(
          child: PdfViewer.file(
            _pdfPath!,
            params: const PdfViewerParams(
              enableTextSelection: true,
            ),
          ),
        ),
        Positioned(
          top: 8,
          right: 8,
          child: Material(
            color:
                Theme.of(context).colorScheme.surface.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(8),
            child: IconButton(
              icon: const Icon(Icons.swap_horiz, size: 20),
              tooltip: 'Change PDF',
              onPressed: _pickReplacementPdf,
            ),
          ),
        ),
      ],
    );
  }
}
