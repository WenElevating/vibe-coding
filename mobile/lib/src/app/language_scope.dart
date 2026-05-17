import 'package:flutter/widgets.dart';

import 'language_controller.dart';

class LanguageScope extends InheritedNotifier<LanguageController> {
  const LanguageScope({
    super.key,
    required LanguageController controller,
    required super.child,
  }) : super(notifier: controller);

  static LanguageController watch(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<LanguageScope>();
    assert(scope != null, 'LanguageScope not found in widget tree');
    return scope!.notifier!;
  }

  static LanguageController read(BuildContext context) {
    final element = context
        .getElementForInheritedWidgetOfExactType<LanguageScope>()
        ?.widget as LanguageScope?;
    assert(element != null, 'LanguageScope not found in widget tree');
    return element!.notifier!;
  }
}
