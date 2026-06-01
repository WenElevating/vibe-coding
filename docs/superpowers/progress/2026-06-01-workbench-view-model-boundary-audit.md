# Workbench ViewModel Boundary Audit

## Candidate State Groups

- Route state: route workspace id, active route name, active conversation route id.
- Conversation event state: event list, message list, pagination cursors, historical load flags, optimistic user message reconciliation.
- Draft attachment state: draft attachments, validation, preview binding, client message id lifecycle.
- Approval/model state: approval responses, active run cancellation, selected adapter/model, unsupported model notice.

## Allowed Dependency Direction

- `WorkbenchViewModel` coordinates all groups.
- Pure helper/value objects may depend on immutable input values only.
- Candidate state groups must not hold references to each other.
- Route-derived facts are passed as values into helpers that need them.

## Cycle Check

- Draft attachment helpers may receive active conversation id as a value, but must not read route state directly.
- Approval helpers may return effects that the ViewModel applies to event and route state, but must not mutate both groups directly.
- Event helpers may rebuild messages from event inputs, but must not navigate routes.
- Model update handling currently depends on selected adapter state, active conversation id, repository mutation, and draft attachment revalidation. Splitting it into an independent mutable object would create cross-object coordination instead of reducing coupling.
- Event pagination currently updates event windows, message projection, loading flags, historical cursors, and attachment preview binding. This should remain coordinated by `WorkbenchViewModel` unless extracted as pure functions.

## Test Gaps

- Existing tests covered repository-backed workspace selection and route entry behavior, but not direct route transition invariants.
- Existing reducer tests covered approvals, attachments, and message projection, but `WorkbenchViewModel` lacked tests for historical page merge behavior.
- Existing tests did not pin model update rejection behavior against route/active conversation state.
- Existing tests did not pin question/approval repository delegation against route mutation.

## Added Coverage

- `route transitions keep workspace and conversation route ids consistent`
- `older event page prepends events without duplicating existing messages`
- `selectModel preserves selected model when repository rejects update`
- `conversation question answer delegates without route mutation`
- `conversation approval delegates without route mutation`

## Extraction Decision

- Extract pure helpers/value objects first.
- Keep coupled mutable state in `WorkbenchViewModel` until tests prove a clean boundary.
- Do not split route, event pagination, draft attachment validation, model update, and approval response into separate mutable owners if doing so creates references between those owners.
