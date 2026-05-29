import '../../../data/repositories/cached_conversation_repository.dart';
import '../../../data/repositories/cached_run_repository.dart';
import '../../../data/repositories/cli_adapter_repository.dart';
import '../../../data/repositories/workspace_repository.dart';
import '../../../domain/repositories/diagnostics_repository.dart';
import '../../../services/asr_model_manager.dart';
import '../../../services/speech_input_contract.dart';
import 'attachments/attachment_preview_cache.dart';

class WorkbenchDependencies {
  const WorkbenchDependencies({
    required this.adapterRepository,
    required this.asrModelManager,
    required this.conversationRepository,
    required this.diagnosticsRepository,
    required this.runRepository,
    required this.speechInputServiceBuilder,
    required this.workspaceRepository,
    this.attachmentPreviewCache = const NoopAttachmentPreviewCache(),
  });

  final AttachmentPreviewCache attachmentPreviewCache;
  final CliAdapterRepository adapterRepository;
  final AsrModelManager asrModelManager;
  final CachedConversationRepository conversationRepository;
  final DiagnosticsRepository diagnosticsRepository;
  final CachedRunRepository runRepository;
  final SpeechInputServiceBuilder speechInputServiceBuilder;
  final WorkspaceRepository workspaceRepository;
}
