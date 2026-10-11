import 'package:flutter/material.dart';

import '../models/item.dart';

/// One item as listed under a day: its title, its description muted beneath
/// it, and a "weekly" marker on recurring items.
class ItemTile extends StatelessWidget {
  const ItemTile({super.key, required this.item});

  final Item item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = TextStyle(color: theme.colorScheme.outline);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(item.title)),
              if (item.kind is Recurring)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(
                    'weekly',
                    style: theme.textTheme.labelSmall?.merge(muted),
                  ),
                ),
            ],
          ),
          if (item.description.isNotEmpty)
            Text(
              item.description.join('\n'),
              style: theme.textTheme.bodySmall?.merge(muted),
            ),
        ],
      ),
    );
  }
}
