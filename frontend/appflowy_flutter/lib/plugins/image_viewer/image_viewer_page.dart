import 'dart:convert';
import 'dart:io';

import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flowy_infra/file_picker/file_picker_service.dart';
import 'package:flutter/material.dart';

/// Displays an image file full-screen with zoom/pan support.
///
/// The file path is read from the view's `extra` JSON (`image_path` key),
/// which is set atomically during view creation by [ViewAddButton].
/// A "swap" button allows replacing the image after initial creation.
class ImageViewerPage extends StatefulWidget {
  const ImageViewerPage({
    super.key,
    required this.view,
  });

  final ViewPB view;

  @override
  State<ImageViewerPage> createState() => _ImageViewerPageState();
}

class _ImageViewerPageState extends State<ImageViewerPage> {
  String? _imagePath;

  @override
  void initState() {
    super.initState();
    _imagePath = _readImagePath();
  }

  String? _readImagePath() {
    try {
      if (widget.view.extra.isNotEmpty) {
        final ext = jsonDecode(widget.view.extra) as Map<String, dynamic>;
        final path = ext['image_path'] as String?;
        if (path != null && path.isNotEmpty && File(path).existsSync()) {
          return path;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Let the user swap the image for this view.
  Future<void> _pickReplacementImage() async {
    final result = await getIt<FilePickerService>().pickFiles(
      dialogTitle: '',
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'],
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
    ext['image_path'] = filePath;

    await ViewBackendService.updateView(
      viewId: widget.view.id,
      extra: jsonEncode(ext),
    );

    if (!mounted) return;
    setState(() => _imagePath = filePath);
  }

  @override
  Widget build(BuildContext context) {
    if (_imagePath == null) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _pickReplacementImage,
        child: Center(
          child: Text(
            'Click to select image',
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
          child: InteractiveViewer(
            minScale: 0.5,
            maxScale: 6,
            child: Center(
              child: Image.file(
                File(_imagePath!),
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return Text(
                    'Unable to load image',
                    style: Theme.of(context).textTheme.bodyMedium,
                  );
                },
              ),
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
              tooltip: 'Change image',
              onPressed: _pickReplacementImage,
            ),
          ),
        ),
      ],
    );
  }
}
