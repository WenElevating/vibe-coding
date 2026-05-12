import 'package:flutter/foundation.dart';

import '../../../models/protocol.dart';
import '../../../shell/app_snapshot.dart';

class AdaptersViewModel extends ChangeNotifier {
  AdaptersViewModel({required AppSnapshot snapshot})
      : _adapters = List.unmodifiable(snapshot.adapters),
        _extensions = List.unmodifiable(snapshot.extensions);

  List<AdapterStatus> _adapters;
  List<ExtensionSummary> _extensions;

  List<AdapterStatus> get adapters => _adapters;
  List<ExtensionSummary> get extensions => _extensions;

  void updateFromSnapshot(AppSnapshot snapshot) {
    _adapters = List.unmodifiable(snapshot.adapters);
    _extensions = List.unmodifiable(snapshot.extensions);
    notifyListeners();
  }
}
