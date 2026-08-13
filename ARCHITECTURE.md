# Architecture

Konomi is a single-target SwiftUI application. `KonomiApp` creates the SwiftData container and blocks normal navigation until persistence bootstrap succeeds. `ContentView` owns the three top-level destinations: Taste, Library, and Discover.

## Boundaries

- `Models/` contains SwiftData entities and local navigation state.
- `Services/` contains API clients, importers, AI orchestration, key storage, and transactional persistence helpers.
- `Views/` reads models and services but does not own remote request construction or persistence recovery policy.
- `Utilities/KonomiTheme.swift` exposes semantic visual roles backed by adaptive asset colors.

All personal library data is on-device. Third-party calls go directly from the device with user-supplied keys. There is no proxy, account service, CloudKit container, analytics SDK, or production environment configuration in this snapshot.

## Data flow

1. Persistence bootstrap opens the production store, seeds the singleton settings row, and applies idempotent row hygiene.
2. Library mutations write through the SwiftData model context; destructive actions that offer Undo capture value snapshots rather than retaining deleted model objects.
3. Search services build semantic query items and map external results into transient candidates.
4. Taste analysis builds a bounded evidence set from the local library, requests prompt-constrained JSON, repairs only structurally recoverable output, and rejects malformed or out-of-focus rows.
5. A successful generation atomically replaces the prior generated snapshot; failures preserve the last good state.

## Trade-offs

- Bring-your-own keys avoid an operating backend but add onboarding friction.
- Snapshot replacement keeps generated content understandable but intentionally provides no recommendation history.
- Raw HTTP avoids SDK coupling but requires request-shape and parser regression tests.
- Device-local storage maximizes privacy but means the CSV export is a summary, not a complete backup.
