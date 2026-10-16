import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';

class ReferencePoint {
  const ReferencePoint({required this.lat, required this.lng, this.label});

  final double lat;
  final double lng;
  final String? label;
}

class SusForm {
  const SusForm({required this.items, required this.choices});

  final List<String> items;
  final List<int> choices;
}

class EvaluationRepository {
  EvaluationRepository(this._api);

  final ApiClient _api;

  Future<ReferencePoint?> currentReference() {
    return _api.get<ReferencePoint?>(ApiEndpoints.evaluationReference, (
      dynamic data,
    ) {
      if (data is! Map<String, dynamic>) return null;
      final Object? raw = data['reference'];
      if (raw is! Map<String, dynamic>) return null;
      final Object? lat = raw['lat'];
      final Object? lng = raw['lng'];
      if (lat is! num || lng is! num) return null;
      final Object? label = raw['label'];
      return ReferencePoint(
        lat: lat.toDouble(),
        lng: lng.toDouble(),
        label: label is String ? label : null,
      );
    });
  }

  Future<void> saveReference({
    required double lat,
    required double lng,
    String? label,
  }) {
    return _api.post<void>(
      ApiEndpoints.evaluationReference,
      (dynamic _) {},
      body: <String, dynamic>{
        'lat': lat,
        'lng': lng,
        if (label != null && label.trim().isNotEmpty) 'label': label.trim(),
      },
    );
  }

  Future<SusForm> susForm() {
    return _api.get<SusForm>(ApiEndpoints.evaluationSus, (dynamic data) {
      if (data is! Map<String, dynamic>) {
        return const SusForm(items: <String>[], choices: <int>[1, 2, 3, 4, 5]);
      }
      final List<String> items = data['items'] is List
          ? (data['items'] as List).whereType<String>().toList(growable: false)
          : const <String>[];
      final List<int> choices = data['choices'] is List
          ? (data['choices'] as List)
                .whereType<num>()
                .map((num n) => n.toInt())
                .toList(growable: false)
          : const <int>[1, 2, 3, 4, 5];
      return SusForm(items: items, choices: choices);
    });
  }

  Future<void> submitSus(List<int> answers) {
    return _api.post<void>(
      ApiEndpoints.evaluationSus,
      (dynamic _) {},
      body: <String, dynamic>{'answers': answers},
    );
  }
}

final Provider<EvaluationRepository> evaluationRepositoryProvider =
    Provider<EvaluationRepository>((Ref ref) {
      return EvaluationRepository(ref.watch(apiClientProvider));
    });
