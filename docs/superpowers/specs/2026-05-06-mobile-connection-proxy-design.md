# Mobile Connection And Proxy Configuration Design

## Problem

The mobile app currently starts by constructing a daemon client for a fixed local address and loading the app snapshot. When that connection fails, the user lands on a retry-only error page. This creates three problems:

- A phone or another LAN device may not share the desktop machine's `127.0.0.1`.
- System proxy settings can intercept local daemon traffic and return opaque failures such as empty `502` responses.
- After failure, the user cannot edit the daemon address or proxy policy in place.

The startup experience needs to make the connection target and network policy explicit before entering the app.

## Goals

- Show a connection page on startup before loading workspaces or sessions.
- Let users edit the daemon address before each connection attempt.
- Persist the last successful address and proxy configuration.
- Support three proxy modes: direct, system proxy, and manual proxy.
- Keep local and private LAN daemon targets direct by default, even when system or manual proxy mode is selected.
- Keep failure recovery on the connection page so users can edit settings and retry immediately.
- Match the existing in-app mobile UI style instead of using a separate promotional or AI-styled launch screen.

## Non-Goals

- Do not redesign the main tab shell, workspace pages, or coding workbench.
- Do not add a recent connections list in this iteration.
- Do not change daemon pairing semantics. Existing automatic pairing behavior remains for now.
- Do not add a "proxy LAN targets too" advanced switch yet. Private addresses remain direct by default.

## UX Design

The startup route becomes a first-class connection gate. It should visually feel like a sibling of the existing workspace and settings pages: dark app background, compact top bar, thin dividers, restrained panels, and task-oriented controls. It should not use a large hero mark, decorative glow, purple-blue launch gradients, or glassmorphism.

The page structure:

```text
Top bar
Connection
Last successful: 127.0.0.1:4317

Connection address
[ 127.0.0.1:4317                         ]

Network proxy
[ Direct        selected ]
[ System proxy           ]
[ Manual proxy           ]

When manual proxy is selected:
[ http://192.168.20.18:27890              ]

Status
Not connected
Target: http://127.0.0.1:4317
Proxy: Direct

Primary action
Connect
```

Failure remains on the same page. Address and proxy controls stay editable. The page shows a short readable error and keeps technical detail secondary:

```text
Connection failed
The daemon returned an empty 502 response. This can happen when a proxy or gateway intercepts the request.

Target: http://127.0.0.1:4317
Proxy: System proxy

Primary action: Reconnect
```

The user can change the address, switch proxy mode, edit the manual proxy, and reconnect without navigating away.

## Connection State

The startup connection controller owns these states:

- `idle`: the connection page is editable and no request is running.
- `validating`: address and proxy inputs are being normalized and checked.
- `connecting`: the client is probing daemon health.
- `loadingSnapshot`: daemon health succeeded and the app snapshot is loading.
- `connected`: snapshot is ready and the main app can render.
- `failed`: the last attempt failed, controls remain editable.

Suggested status messages:

- `Resolving connection address`
- `Connecting to daemon`
- `Checking daemon health`
- `Syncing workspace state`

The controller should create a fresh `DaemonClient` for each connection attempt so address and proxy changes are always honored.

## Data Model

Persist a small connection configuration locally:

```dart
enum DaemonProxyMode {
  direct,
  system,
  manual,
}

class DaemonConnectionConfig {
  const DaemonConnectionConfig({
    required this.addressInput,
    required this.proxyMode,
    required this.manualProxyInput,
  });

  final String addressInput;
  final DaemonProxyMode proxyMode;
  final String manualProxyInput;
}
```

Defaults:

- `addressInput`: `127.0.0.1:4317`
- `proxyMode`: `direct`
- `manualProxyInput`: empty

Only successful configurations are persisted. Failed edits stay in page state until the user succeeds or leaves the app.

## Address Normalization

The connection page accepts compact LAN-friendly input:

- `127.0.0.1` becomes `http://127.0.0.1:4317`
- `192.168.1.23` becomes `http://192.168.1.23:4317`
- `host.local:4317` becomes `http://host.local:4317`
- `http://host:1234` keeps its scheme and port

Invalid or empty addresses show inline validation and do not issue network requests.

## Proxy Policy

The daemon client should be created from both the base URI and the selected proxy mode.

Modes:

- `direct`: always returns `DIRECT`.
- `system`: use system proxy behavior for non-private targets, but return `DIRECT` for local and private addresses.
- `manual`: return `DIRECT` for local and private addresses; for other targets, return the configured proxy.

Local and private targets:

- `localhost`
- `127.0.0.0/8`
- `::1`
- `10.0.0.0/8`
- `172.16.0.0/12`
- `192.168.0.0/16`

Manual proxy validation accepts `http://host:port` and compact `host:port`, normalizing compact input to an HTTP proxy. Invalid manual proxy input blocks the connection attempt with an inline error.

This policy prevents system proxies from hijacking local daemon requests while preserving explicit proxy support for users who need it.

## Error Handling

The client should continue to wrap invalid daemon responses as `DaemonClientException` with structured `error` and `message` fields. The connection page should translate common failures into useful summaries:

- Empty or invalid JSON response: "The daemon returned an invalid response."
- `502` with empty response: "A proxy or gateway may have intercepted the daemon request."
- Connection refused: "No daemon is listening at this address."
- Timeout: "The daemon did not respond in time."
- Invalid address or proxy input: inline form error, no request sent.

Technical detail remains visible in small secondary text for troubleshooting.

## Component Boundaries

- `DaemonConnectionConfigStore`: loads and saves the last successful configuration.
- `DaemonConnectionController`: normalizes input, creates clients, runs health and snapshot loading, exposes UI state.
- `DaemonClientFactory`: creates `DaemonClient` instances with the selected proxy policy.
- `ConnectionConfigPage`: renders the mobile connection UI and owns text fields.
- `MobileUi`: switches between connection page and `MainTabsPage`.

The existing `AppSnapshot.load(client)` path remains the main application entry after connection succeeds.

## Testing

Add or update tests for:

- Address normalization:
  - `127.0.0.1` to `http://127.0.0.1:4317`
  - `192.168.1.23` to `http://192.168.1.23:4317`
  - explicit scheme and port preserved
  - empty or invalid input rejected before network access
- Proxy policy:
  - direct always returns `DIRECT`
  - system returns `DIRECT` for loopback and private LAN addresses
  - manual returns `DIRECT` for loopback and private LAN addresses
  - manual returns `PROXY host:port` for non-private targets
  - invalid manual proxy input creates a validation error
- Connection page behavior:
  - initial page renders stored address and proxy mode
  - failed connection keeps controls editable
  - reconnect uses the latest field values
  - successful connection persists config and enters the main tab page
- Existing daemon response handling:
  - empty response becomes `DaemonClientException`
  - invalid JSON becomes `DaemonClientException`

Verification should include:

- `flutter analyze`
- targeted connection and daemon client tests
- full `flutter test --no-pub`

When a system proxy is configured during testing, set `NO_PROXY=localhost,127.0.0.1,::1` for Flutter tester itself so the test runner's local control channel is not intercepted.
