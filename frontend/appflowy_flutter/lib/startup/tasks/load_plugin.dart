import 'package:appflowy/plugins/ai_chat/chat.dart';
import 'package:appflowy/plugins/database/calendar/calendar.dart';
import 'package:appflowy/plugins/database/board/board.dart';
import 'package:appflowy/plugins/database/grid/grid.dart';
import 'package:appflowy/plugins/database_document/database_document_plugin.dart';
import 'package:appflowy/plugins/excalidraw/excalidraw.dart';
import 'package:appflowy/plugins/image_viewer/image_viewer.dart';
import 'package:appflowy/plugins/pdf_viewer/pdf_viewer.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/plugins/blank/blank.dart';
import 'package:appflowy/plugins/document/document.dart';
import 'package:appflowy/plugins/trash/trash.dart';

class PluginLoadTask extends LaunchTask {
  const PluginLoadTask();

  @override
  LaunchTaskType get type => LaunchTaskType.dataProcessing;

  @override
  Future<void> initialize(LaunchContext context) async {
    await super.initialize(context);

    registerPlugin(builder: BlankPluginBuilder(), config: BlankPluginConfig());
    registerPlugin(builder: TrashPluginBuilder(), config: TrashPluginConfig());
    registerPlugin(builder: DocumentPluginBuilder());
    registerPlugin(builder: GridPluginBuilder(), config: GridPluginConfig());
    registerPlugin(builder: BoardPluginBuilder(), config: BoardPluginConfig());
    registerPlugin(
      builder: CalendarPluginBuilder(),
      config: CalendarPluginConfig(),
    );
    registerPlugin(
      builder: DatabaseDocumentPluginBuilder(),
      config: DatabaseDocumentPluginConfig(),
    );
    registerPlugin(
      builder: DatabaseDocumentPluginBuilder(),
      config: DatabaseDocumentPluginConfig(),
    );
    registerPlugin(
      builder: AIChatPluginBuilder(),
      config: AIChatPluginConfig(),
    );
    registerPlugin(
      builder: PdfViewerPluginBuilder(),
      config: PdfViewerPluginConfig(),
    );
    registerPlugin(
      builder: ExcalidrawPluginBuilder(),
      config: ExcalidrawPluginConfig(),
    );
    registerPlugin(
      builder: ImageViewerPluginBuilder(),
      config: ImageViewerPluginConfig(),
    );
  }
}
