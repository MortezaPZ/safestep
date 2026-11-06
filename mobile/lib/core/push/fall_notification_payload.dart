import 'dart:convert';

class FallNotificationPayload {
  const FallNotificationPayload({
    required this.eventId,
    required this.startedAt,
    required this.deadline,
  });

  final String eventId;
  final DateTime startedAt;
  final DateTime deadline;

  String encode() => jsonEncode(<String, Object>{
        'kind': 'fall_check',
        'eventId': eventId,
        'startedAt': startedAt.toUtc().toIso8601String(),
        'deadline': deadline.toUtc().toIso8601String(),
      });

  static FallNotificationPayload? tryParse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic> || decoded['kind'] != 'fall_check') {
        return null;
      }
      final Object? eventId = decoded['eventId'];
      final Object? startedAt = decoded['startedAt'];
      final Object? deadline = decoded['deadline'];
      if (eventId is! String ||
          eventId.isEmpty ||
          startedAt is! String ||
          deadline is! String) {
        return null;
      }
      final DateTime? parsedStart = DateTime.tryParse(startedAt)?.toLocal();
      final DateTime? parsedDeadline = DateTime.tryParse(deadline)?.toLocal();
      if (parsedStart == null || parsedDeadline == null) return null;
      return FallNotificationPayload(
        eventId: eventId,
        startedAt: parsedStart,
        deadline: parsedDeadline,
      );
    } on FormatException {
      return null;
    }
  }

  int remainingSeconds(DateTime now) {
    final int remaining = deadline.difference(now).inSeconds;
    return remaining < 0 ? 0 : remaining;
  }
}
