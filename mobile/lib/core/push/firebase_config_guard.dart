/// Runs optional Firebase setup without making a missing native project file
/// fatal to app startup.
Future<bool> initializeFirebaseSafely(
  Future<void> Function() initialize,
) async {
  try {
    await initialize();
    return true;
  } catch (_) {
    return false;
  }
}
