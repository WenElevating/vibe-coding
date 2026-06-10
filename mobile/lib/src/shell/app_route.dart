enum RoutePage { tabs, detail, approval, adapters, notifications, diagnostics }

class AppRoute {
  const AppRoute(this.page, {this.runId});

  const AppRoute.tabs() : this(RoutePage.tabs);

  const AppRoute.detail({String? runId})
      : this(
          RoutePage.detail,
          runId: runId,
        );

  final RoutePage page;
  final String? runId;

  @override
  bool operator ==(Object other) =>
      other is AppRoute && other.page == page && other.runId == runId;

  @override
  int get hashCode => Object.hash(page, runId);
}
