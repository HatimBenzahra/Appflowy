import 'dart:convert';
import 'dart:io';

import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Full-screen Excalidraw editor page.
///
/// Uses a WebView that loads Excalidraw from CDN (esm.sh).
/// Drawing data is persisted in a local JSON file at:
///   {appSupportDir}/excalidraw/{viewId}.json
///
/// Communication with Excalidraw is done via JavaScript channels:
///  - `Flutter` channel: receives save data from JS
///  - `FlutterReady` channel: signals the page is ready to receive data
class ExcalidrawPage extends StatefulWidget {
  const ExcalidrawPage({
    super.key,
    required this.view,
  });

  final ViewPB view;

  @override
  State<ExcalidrawPage> createState() => _ExcalidrawPageState();
}

class _ExcalidrawPageState extends State<ExcalidrawPage> {
  late final WebViewController _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  void _initWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'Flutter',
        onMessageReceived: (message) => _saveData(message.message),
      )
      ..addJavaScriptChannel(
        'FlutterReady',
        onMessageReceived: (_) {
          if (!_ready) {
            _ready = true;
            _loadData();
          }
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            // Fallback: if JS ready signal wasn't received after 5s,
            // try loading data anyway.
            Future.delayed(const Duration(seconds: 5), () {
              if (!_ready) {
                _ready = true;
                _loadData();
              }
            });
          },
        ),
      )
      ..loadHtmlString(_excalidrawHtml);
  }

  /// Read the optional imported file path from the view's extra JSON.
  String? _readImportedFilePath() {
    try {
      if (widget.view.extra.isNotEmpty) {
        final ext = jsonDecode(widget.view.extra) as Map<String, dynamic>;
        final path = ext['excalidraw_file_path'] as String?;
        if (path != null && path.isNotEmpty) {
          return path;
        }
      }
    } catch (_) {}
    return null;
  }

  Future<File> _getDataFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/excalidraw/${widget.view.id}.json');
  }

  /// Load drawing data into the WebView.
  ///
  /// Priority:
  /// 1. Local save file (user may have edited after import)
  /// 2. Imported .excalidraw file from the view's extra JSON
  /// 3. Blank canvas (no data to load)
  Future<void> _loadData() async {
    try {
      // 1. Check local save file first (has latest edits)
      final localFile = await _getDataFile();
      if (await localFile.exists()) {
        final data = await localFile.readAsString();
        final escaped = jsonEncode(data);
        await _controller.runJavaScript('loadExcalidrawData($escaped)');
        return;
      }

      // 2. Check imported file path from view.extra
      final importedPath = _readImportedFilePath();
      if (importedPath != null) {
        final importedFile = File(importedPath);
        if (await importedFile.exists()) {
          final data = await importedFile.readAsString();
          final escaped = jsonEncode(data);
          await _controller.runJavaScript('loadExcalidrawData($escaped)');
          // Save a copy locally so future loads use the local file
          await _saveData(data);
          return;
        }
      }

      // 3. No data — blank canvas (nothing to do)
    } catch (e) {
      debugPrint('Excalidraw: failed to load data: $e');
    }
  }

  Future<void> _saveData(String jsonData) async {
    try {
      final file = await _getDataFile();
      final dir = file.parent;
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      await file.writeAsString(jsonData);
    } catch (e) {
      debugPrint('Excalidraw: failed to save data: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return WebViewWidget(controller: _controller);
  }

  // ---------------------------------------------------------------------------
  // Self-contained HTML that loads Excalidraw from CDN.
  //
  // React 18 and Excalidraw are loaded as ES modules from esm.sh.
  // The ?deps parameter ensures Excalidraw uses the same React instance.
  //
  // Data flow:
  //   JS → Flutter: Flutter.postMessage(jsonString)  (auto-save on change)
  //   Flutter → JS: loadExcalidrawData(jsonString)   (restore saved state)
  // ---------------------------------------------------------------------------
  static const _excalidrawHtml = '''
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    html, body, #root { width: 100%; height: 100%; overflow: hidden; }
    #loading {
      display: flex;
      align-items: center;
      justify-content: center;
      width: 100%;
      height: 100%;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      color: #888;
      font-size: 14px;
    }
    #error {
      display: none;
      align-items: center;
      justify-content: center;
      width: 100%;
      height: 100%;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      color: #c0392b;
      font-size: 14px;
      padding: 24px;
      text-align: center;
    }
  </style>
</head>
<body>
  <div id="root">
    <div id="loading">Loading Excalidraw…</div>
  </div>
  <div id="error"></div>
  <script type="module">
    try {
      const [ReactMod, ReactDOMMod, ExcalidrawMod] = await Promise.all([
        import('https://esm.sh/react@18.2.0'),
        import('https://esm.sh/react-dom@18.2.0/client'),
        import('https://esm.sh/@excalidraw/excalidraw@0.17.6?deps=react@18.2.0,react-dom@18.2.0'),
      ]);

      const React = ReactMod.default || ReactMod;
      const { createRoot } = ReactDOMMod;
      const { Excalidraw } = ExcalidrawMod;
      const { createElement } = React;

      let excalidrawAPI = null;
      let saveTimer = null;

      function App() {
        return createElement(Excalidraw, {
          excalidrawAPI: function(api) { excalidrawAPI = api; },
          onChange: function(elements, appState) {
            clearTimeout(saveTimer);
            saveTimer = setTimeout(function() {
              try {
                const data = JSON.stringify({
                  elements: elements.map(function(el) {
                    return Object.assign({}, el);
                  }),
                  appState: {
                    viewBackgroundColor: appState.viewBackgroundColor,
                    theme: appState.theme,
                  },
                });
                Flutter.postMessage(data);
              } catch (e) {
                // Flutter channel not ready yet, ignore.
              }
            }, 2000);
          },
        });
      }

      const root = createRoot(document.getElementById('root'));
      root.render(createElement(App));

      // Called by Flutter to restore saved drawing data.
      window.loadExcalidrawData = function(jsonStr) {
        if (!excalidrawAPI || !jsonStr) return;
        try {
          const data = JSON.parse(jsonStr);
          excalidrawAPI.updateScene({
            elements: data.elements || [],
            appState: data.appState || {},
          });
        } catch (e) {
          console.error('Excalidraw: failed to load data:', e);
        }
      };

      // Notify Flutter that Excalidraw is ready.
      setTimeout(function() {
        try { FlutterReady.postMessage('ready'); } catch(e) {}
      }, 1500);

    } catch (e) {
      document.getElementById('root').style.display = 'none';
      const errEl = document.getElementById('error');
      errEl.style.display = 'flex';
      errEl.textContent = 'Failed to load Excalidraw: ' + e.message +
        '. Please check your internet connection.';
    }
  </script>
</body>
</html>
''';
}
