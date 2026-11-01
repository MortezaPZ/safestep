# App Shell

[SafeStep Mobile overview](../../README.md)

This folder creates the top-level Flutter application and central route table.

- `app.dart` configures localization, accessibility-aware scaling, themes, and app-wide realtime state.
- `router.dart` maps public, authenticated, and role-specific routes to feature screens.

Add new screens to their feature folders first, then register the route here. Keep product logic out of the app shell.
