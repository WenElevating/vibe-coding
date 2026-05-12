import '../../models/protocol.dart';

abstract class AdapterRepository {
  Future<List<AdapterStatus>> listAdapters();

  Future<List<ShortcutCommand>> listShortcuts();

  Future<List<CommandTemplate>> listCommandTemplates();

  Future<List<ExtensionSummary>> listExtensions();
}
