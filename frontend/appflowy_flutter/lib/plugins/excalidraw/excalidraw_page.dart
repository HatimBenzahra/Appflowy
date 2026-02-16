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
  HttpServer? _server;
  bool _ready = false;
  bool _loaded = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  @override
  void dispose() {
    _server?.close(force: true);
    super.dispose();
  }

  void _initWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setOnConsoleMessage((message) {
        debugPrint('Excalidraw JS [${message.level}]: ${message.message}');
      })
      ..addJavaScriptChannel(
        'Flutter',
        onMessageReceived: (message) => _saveData(message.message),
      )
      ..addJavaScriptChannel(
        'FlutterReady',
        onMessageReceived: (_) {
          if (!_ready) {
            _ready = true;
            if (mounted) setState(() => _loaded = true);
            _loadData();
          }
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            // Fallback: if JS ready signal wasn't received after 15s,
            // try loading data anyway (CDN can be slow).
            Future.delayed(const Duration(seconds: 15), () {
              if (!_ready) {
                _ready = true;
                if (mounted) setState(() => _loaded = true);
                _loadData();
              }
            });
          },
        ),
      );

    // Serve the HTML via a local HTTP server so that WKWebView gets a proper
    // http:// origin. Both loadHtmlString (about:blank) and loadFile (file://)
    // block ES module dynamic imports from CDN due to CORS/security policies.
    _startServerAndLoad();
  }

  Future<void> _startServerAndLoad() async {
    try {
      final server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0, // random available port
      );
      _server = server;

      server.listen((request) {
        request.response
          ..headers.contentType = ContentType.html
          ..headers.set('Access-Control-Allow-Origin', '*')
          ..write(_excalidrawHtml)
          ..close();
      });

      final url = 'http://127.0.0.1:${server.port}/';
      debugPrint('Excalidraw: serving on $url');
      await _controller.loadRequest(Uri.parse(url));
    } catch (e) {
      debugPrint('Excalidraw: failed to start local server: $e');
      if (mounted) {
        setState(() => _error = 'Failed to load Excalidraw editor: $e');
      }
    }
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
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error!,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return Stack(
      children: [
        Positioned.fill(
          child: WebViewWidget(controller: _controller),
        ),
        if (!_loaded)
          Positioned.fill(
            child: Container(
              color: Theme.of(context).colorScheme.surface,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(
                      'Loading Excalidraw...',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.5),
                          ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Self-contained HTML that loads Excalidraw using UMD builds.
  //
  // React 18, ReactDOM, and Excalidraw are loaded as UMD scripts from unpkg.
  // UMD builds expose globals (React, ReactDOM, ExcalidrawLib) and work in
  // any WebView context — unlike ES modules which fail in WKWebView.
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
    .excalidraw .App-menu_top .buttonList { flex-wrap: wrap; }
    #loading-screen {
      display: flex;
      align-items: center;
      justify-content: center;
      width: 100%;
      height: 100%;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      color: #888;
      font-size: 14px;
    }
    #error-screen {
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
  <script>
    window.EXCALIDRAW_ASSET_PATH = "https://unpkg.com/@excalidraw/excalidraw@0.17.6/dist/prod/";
  </script>
  <script src="https://unpkg.com/react@18.2.0/umd/react.production.min.js"></script>
  <script src="https://unpkg.com/react-dom@18.2.0/umd/react-dom.production.min.js"></script>
  <script src="https://unpkg.com/@excalidraw/excalidraw@0.17.6/dist/excalidraw.production.min.js"></script>
</head>
<body>
  <div id="root">
    <div id="loading-screen">Loading Excalidraw…</div>
  </div>
  <div id="error-screen"></div>
  <script>
    (function() {
      try {
        if (typeof ExcalidrawLib === 'undefined') {
          throw new Error('ExcalidrawLib not loaded. Check internet connection.');
        }

        var Excalidraw = ExcalidrawLib.Excalidraw;
        var createElement = React.createElement;
        var excalidrawAPI = null;
        var saveTimer = null;

        function App() {
          return createElement(
            'div',
            { style: { width: '100%', height: '100vh' } },
            createElement(Excalidraw, {
              excalidrawAPI: function(api) { excalidrawAPI = api; },
              onChange: function(elements, appState) {
                clearTimeout(saveTimer);
                saveTimer = setTimeout(function() {
                  try {
                    var data = JSON.stringify({
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
            })
          );
        }

        var root = ReactDOM.createRoot(document.getElementById('root'));
        root.render(createElement(App));

        // Called by Flutter to restore saved drawing data.
        window.loadExcalidrawData = function(jsonStr) {
          if (!excalidrawAPI || !jsonStr) return;
          try {
            var data = JSON.parse(jsonStr);
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
        var errEl = document.getElementById('error-screen');
        errEl.style.display = 'flex';
        errEl.textContent = 'Failed to load Excalidraw: ' + e.message;
      }
    })();
  </script>
</body>
</html>
''';
}
