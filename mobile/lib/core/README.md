# Shared Mobile Foundations

[SafeStep Mobile overview](../../README.md)

This folder holds services and UI foundations reused across product features.

- `accessibility/`: locale, contrast, text scale, and motion preferences.
- `constants/`: build-time app and API settings.
- `device/`: device registration.
- `network/`: REST and Socket.IO clients, endpoint definitions, and server-origin handling.
- `push/`: push-notification setup and routing callbacks.
- `storage/`: secure session and token storage.
- `theme/`: colors, spacing, typography, motion, and app themes.
- `utils/`: shared formatting and error types.
- `widgets/`: common buttons, cards, navigation, maps, and state views.

Feature modules should depend on these shared services instead of duplicating platform or transport code.
