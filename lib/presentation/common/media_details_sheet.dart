import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/l10n.dart';
import '../../domain/models/media_item.dart';

Future<void> showMediaDetailsSheet(BuildContext context, MediaItem item) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      final exists = File(item.privatePath).existsSync();
      final sizeMb = (item.sizeBytes / (1024 * 1024)).toStringAsFixed(2);
      final fmt = DateFormat.yMMMd().add_jm();
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Details',
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              _row(context.l10n.nameLabel, item.originalName),
              _row(
                  context.l10n.typeLabel,
                  item.isVideo
                      ? context.l10n.typeVideo
                      : context.l10n.typeImage),
              _row('MIME', item.mimeType),
              _row(context.l10n.sizeLabel, '$sizeMb MB'),
              if (item.width != null && item.height != null)
                _row('Dimensions', '${item.width} × ${item.height}'),
              _row(context.l10n.ratingLabel, '${item.rating} / 3 hearts'),
              _row('Added', fmt.format(item.dateAdded.toLocal())),
              if (item.dateTaken != null)
                _row('Taken', fmt.format(item.dateTaken!.toLocal())),
              _row(context.l10n.pathLabel, item.privatePath),
              _row('On disk', exists ? 'Yes' : 'Missing'),
            ],
          ),
        ),
      );
    },
  );
}

Widget _row(String k, String v) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 96,
          child: Text(
            k,
            style: const TextStyle(
              color: Colors.white54,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
        Expanded(
          child: Text(
            v,
            style: const TextStyle(fontSize: 13),
          ),
        ),
      ],
    ),
  );
}
