import '../../../../domain/repositories/conversation_repository.dart';
import '../../../../models/protocol.dart';

String? normalizeWorkbenchModel(String? model) {
  final trimmed = model?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  return trimmed;
}

String? preferredWorkbenchModelFor(AdapterStatus? adapter) {
  final models = adapter?.models ?? const <AdapterModelOption>[];
  if (models.isEmpty) return null;
  final selectedModel = normalizeWorkbenchModel(adapter?.selectedModel);
  if (selectedModel != null &&
      models.any((model) => model.id == selectedModel)) {
    return selectedModel;
  }
  for (final model in models) {
    final id = normalizeWorkbenchModel(model.id);
    if (model.selected && id != null) return id;
  }
  for (final model in models) {
    final id = normalizeWorkbenchModel(model.id);
    if (id != null) return id;
  }
  return null;
}

bool workbenchModelStillAvailable(
  String? model,
  AdapterStatus? adapter,
) {
  final id = normalizeWorkbenchModel(model);
  if (id == null) return true;
  final models = adapter?.models ?? const <AdapterModelOption>[];
  return models.any((model) => model.id == id);
}

bool isUnsupportedWorkbenchModelUpdate(
  ConversationRepositoryException error,
) {
  if (error.statusCode == 405) return true;
  if (error.statusCode != 404) return false;
  return error.code != 'NOT_FOUND';
}
