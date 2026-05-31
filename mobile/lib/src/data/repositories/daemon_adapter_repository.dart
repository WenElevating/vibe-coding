import '../../domain/repositories/adapter_repository.dart';
import '../../models/protocol.dart';
import '../../services/daemon_client.dart';

class DaemonAdapterRepository implements AdapterRepository {
  DaemonAdapterRepository({required DaemonClient client}) : _client = client;

  final DaemonClient _client;

  @override
  Future<List<AdapterStatus>> listAdapters() => _client.listAdapters();

  @override
  Future<List<ShortcutCommand>> listShortcuts() => _client.listShortcuts();

  @override
  Future<List<CommandTemplate>> listCommandTemplates() =>
      _client.listCommandTemplates();

  @override
  Future<List<ExtensionSummary>> listExtensions() => _client.listExtensions();

  Future<List<SlashCommand>> listSlashCommands(String adapterId) =>
      _client.listSlashCommands(adapterId);
}
