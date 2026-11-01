# SafeStep Mobile Source

[Mobile client overview](../README.md)

The application code is divided into the app shell, shared platform services, and user-facing features.

- [app/](<app/README.md>) configures the Flutter app, navigation, and route-level access.
- [core/](<core/README.md>) contains reusable networking, device, storage, notification, accessibility, and design-system code.
- [features/](<features/README.md>) groups product workflows by capability.

Keep feature-specific behavior in its feature module. Put code in `core/` only when multiple features share the same responsibility.
