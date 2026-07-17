import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/import/import_models.dart';

class ShareQueueState {
  const ShareQueueState({this.pending = const [], this.flushing = false});

  final List<ImportSource> pending;
  final bool flushing;

  bool get hasPending => pending.isNotEmpty;
}

/// Owns shared-media queueing across lock and import sessions.
class ShareQueueController extends Notifier<ShareQueueState> {
  @override
  ShareQueueState build() => const ShareQueueState();

  void enqueue(Iterable<ImportSource> sources) {
    final additions = List<ImportSource>.of(sources);
    if (additions.isEmpty) return;
    state = ShareQueueState(
      pending: List.unmodifiable([...state.pending, ...additions]),
      flushing: state.flushing,
    );
  }

  List<ImportSource>? beginFlush() {
    if (state.flushing || state.pending.isEmpty) return null;
    final batch = state.pending;
    state = const ShareQueueState(flushing: true);
    return batch;
  }

  void finishFlush() {
    state = ShareQueueState(pending: state.pending);
  }
}

final shareQueueControllerProvider =
    NotifierProvider<ShareQueueController, ShareQueueState>(
  ShareQueueController.new,
);
