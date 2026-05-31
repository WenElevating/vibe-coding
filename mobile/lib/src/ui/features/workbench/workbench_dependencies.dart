import '../../../data/repositories/cached_conversation_repository.dart';
import '../../../data/repositories/cached_run_repository.dart';
import '../../../data/repositories/cli_adapter_repository.dart';
import '../../../data/repositories/coding_preferences_repository.dart';
import '../../../data/repositories/slash_command_catalog_repository.dart';
import '../../../data/repositories/workspace_repository.dart';
import '../../../domain/repositories/diagnostics_repository.dart';
import '../../../services/asr_model_manager.dart';
import '../../../services/mobile_app_event_bus.dart';
import '../../../services/speech_input_contract.dart';
import '../../../workflows/connection/open_workspace_use_case.dart';
import 'attachments/attachment_preview_cache.dart';

class WorkbenchDependencies {
  WorkbenchDependencies({
    required this.adapterRepository,
    required this.asrModelManager,
    CodingPreferencesRepository? codingPreferencesRepository,
    SlashCommandCatalogRepository? slashCommandCatalogRepository,
    required this.conversationRepository,
    required this.diagnosticsRepository,
    required this.runRepository,
    required this.speechInputServiceBuilder,
    required this.workspaceRepository,
    this.workspaceOpeningUseCase,
    this.attachmentPreviewCache = const NoopAttachmentPreviewCache(),
    this.mobileAppEventBus,
  })  : codingPreferencesRepository =
            codingPreferencesRepository ?? CodingPreferencesRepository(),
        slashCommandCatalogRepository = slashCommandCatalogRepository ??
            SlashCommandCatalogRepository(
              client: (_) async => const [],
            );

  final AttachmentPreviewCache attachmentPreviewCache;
  final CliAdapterRepository adapterRepository;
  final AsrModelManager asrModelManager;
  final CodingPreferencesRepository codingPreferencesRepository;
  final SlashCommandCatalogRepository slashCommandCatalogRepository;
  final CachedConversationRepository conversationRepository;
  final DiagnosticsRepository diagnosticsRepository;
  final CachedRunRepository runRepository;
  final SpeechInputServiceBuilder speechInputServiceBuilder;
  final WorkspaceRepository workspaceRepository;
  final WorkspaceOpeningUseCase? workspaceOpeningUseCase;
  final MobileAppEventBus? mobileAppEventBus;

  WorkbenchDependencies copyWith({
    CodingPreferencesRepository? codingPreferencesRepository,
    SlashCommandCatalogRepository? slashCommandCatalogRepository,
    WorkspaceOpeningUseCase? workspaceOpeningUseCase,
    MobileAppEventBus? mobileAppEventBus,
  }) {
    return WorkbenchDependencies(
      adapterRepository: adapterRepository,
      asrModelManager: asrModelManager,
      codingPreferencesRepository:
          codingPreferencesRepository ?? this.codingPreferencesRepository,
      slashCommandCatalogRepository:
          slashCommandCatalogRepository ?? this.slashCommandCatalogRepository,
      conversationRepository: conversationRepository,
      diagnosticsRepository: diagnosticsRepository,
      runRepository: runRepository,
      speechInputServiceBuilder: speechInputServiceBuilder,
      workspaceRepository: workspaceRepository,
      workspaceOpeningUseCase:
          workspaceOpeningUseCase ?? this.workspaceOpeningUseCase,
      attachmentPreviewCache: attachmentPreviewCache,
      mobileAppEventBus: mobileAppEventBus ?? this.mobileAppEventBus,
    );
  }
}
