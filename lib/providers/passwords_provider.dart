import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/item.dart';
import '../models/item_type.dart';
import 'items_provider.dart';

/// Passwords only (drafts included), derived from [itemsProvider].
final passwordsProvider = Provider<List<Item>>((ref) => ref
    .watch(itemsProvider)
    .where((i) => i.type == ItemType.password)
    .toList());
