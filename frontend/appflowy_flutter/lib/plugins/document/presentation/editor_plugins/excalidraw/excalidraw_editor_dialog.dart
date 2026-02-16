import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

Future<String?> showExcalidrawEditorDialog(
  BuildContext context, {
  required String initialData,
}) {
  return showGeneralDialog<String>(
    context: context,
    barrierLabel: 'Excalidraw',
    transitionDuration: Duration.zero,
    pageBuilder: (_, __, ___) {
      return ExcalidrawEditorDialog(initialData: initialData);
    },
  );
}

class ExcalidrawEditorDialog extends StatefulWidget {
  const ExcalidrawEditorDialog({
    super.key,
    required this.initialData,
  });

  final String initialData;

  @override
  State<ExcalidrawEditorDialog> createState() => _ExcalidrawEditorDialogState();
}

class _ExcalidrawEditorDialogState extends State<ExcalidrawEditorDialog> {
  static const String _bridgeName = 'AppFlowyBridge';

  Completer<String>? _bridgeResultCompleter;
  late final WebViewController _controller;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        _bridgeName,
        onMessageReceived: (message) {
          final completer = _bridgeResultCompleter;
          if (completer != null && !completer.isCompleted) {
            completer.complete(message.message);
          }
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {},
        ),
      )
      ..loadHtmlString(_buildHtml(widget.initialData));
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SafeArea(
        child: Column(
          children: [
            _TopBar(
              isSaving: _isSaving,
              onClose: _close,
              onSave: _save,
            ),
            const Divider(height: 1),
            Expanded(
              child: WebViewWidget(controller: _controller),
            ),
          ],
        ),
      ),
    );
  }

  String _buildHtml(String initialData) {
    final initialDataJson = _sanitizeInitialData(initialData);
    return _excalidrawHtmlTemplate.replaceFirst(
      'window._INITIAL_DATA || {}',
      initialDataJson,
    );
  }

  String _sanitizeInitialData(String rawData) {
    if (rawData.trim().isEmpty) {
      return '{}';
    }
    try {
      final decoded = jsonDecode(rawData);
      if (decoded is Map || decoded is List) {
        return jsonEncode(decoded);
      }
    } catch (_) {
      // Fallback to empty scene data.
    }
    return '{}';
  }

  Future<void> _save() async {
    if (_isSaving) {
      return;
    }

    setState(() => _isSaving = true);
    String drawingData = '{}';

    try {
      _bridgeResultCompleter = Completer<String>();
      await _controller.runJavaScript(
        'window.AppFlowyBridge.postMessage(window.getSceneData());',
      );
      drawingData = await _bridgeResultCompleter!.future.timeout(
        const Duration(seconds: 2),
      );
    } catch (_) {
      try {
        final result = await _controller.runJavaScriptReturningResult(
          'window.getSceneData()',
        );
        drawingData = _normalizeJavaScriptResult(result);
      } catch (_) {
        drawingData = '{}';
      }
    }

    if (!mounted) {
      return;
    }
    Navigator.of(context).pop(drawingData);
  }

  String _normalizeJavaScriptResult(Object result) {
    if (result is String) {
      final trimmed = result.trim();
      if (trimmed.startsWith('"') && trimmed.endsWith('"')) {
        try {
          return jsonDecode(trimmed) as String;
        } catch (_) {
          return trimmed.substring(1, trimmed.length - 1);
        }
      }
      return trimmed;
    }
    return result.toString();
  }

  void _close() {
    Navigator.of(context).pop();
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.isSaving,
    required this.onClose,
    required this.onSave,
  });

  final bool isSaving;
  final VoidCallback onClose;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: Row(
        children: [
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Close',
            icon: const Icon(Icons.close),
            onPressed: onClose,
          ),
          const SizedBox(width: 8),
          const Text(
            'Excalidraw',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: isSaving ? null : onSave,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Save'),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}

const String _excalidrawHtmlTemplate = '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    html, body, #root { width: 100%; height: 100%; overflow: hidden; }
  </style>
</head>
<body>
  <div id="root"></div>
  <script src="https://unpkg.com/react@18/umd/react.production.min.js"></script>
  <script src="https://unpkg.com/react-dom@18/umd/react-dom.production.min.js"></script>
  <script src="https://unpkg.com/@excalidraw/excalidraw/dist/excalidraw.production.min.js"></script>
  <script>
    let excalidrawAPI;
    const initialData = window._INITIAL_DATA || {};
    const App = () => {
      return React.createElement(ExcalidrawLib.Excalidraw, {
        excalidrawAPI: (api) => { excalidrawAPI = api; },
        initialData: initialData,
        UIOptions: { canvasActions: { saveToActiveFile: false, loadScene: false, export: false } }
      });
    };
    const root = ReactDOM.createRoot(document.getElementById('root'));
    root.render(React.createElement(App));

    window.getSceneData = function() {
      if (!excalidrawAPI) return '{}';
      const elements = excalidrawAPI.getSceneElements();
      const appState = excalidrawAPI.getAppState();
      return JSON.stringify({ elements: elements, appState: { viewBackgroundColor: appState.viewBackgroundColor } });
    };
  </script>
</body>
</html>
''';
