import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';

/// Set / clear heart ratings (0–3). Grids re-emit via Drift streams.
class RatingController extends Notifier<void> {
  @override
  void build() {}

  Future<void> setRating(String id, int rating) {
    return ref.read(mediaRepositoryProvider).updateRating(id, rating);
  }

  Future<void> clear(String id) => setRating(id, 0);
}

final ratingControllerProvider =
    NotifierProvider<RatingController, void>(RatingController.new);
