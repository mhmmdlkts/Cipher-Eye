import 'package:cipher_eye/screens/add_new_password_screen.dart';
import 'package:cipher_eye/screens/card_editor_screen.dart';
import 'package:cipher_eye/screens/document_editor_screen.dart';
import 'package:cipher_eye/screens/file_editor_screen.dart';
import 'package:cipher_eye/screens/item_detail_screen.dart';
import 'package:cipher_eye/screens/note_editor_screen.dart';
import 'package:cipher_eye/screens/password_detail_screen.dart';
import 'package:cipher_eye/screens/settings_screen.dart';
import 'package:cipher_eye/screens/vaults_screen.dart';
import 'package:cipher_eye/services/item_service.dart';
import 'package:cipher_eye/services/clipboard_service.dart';
import 'package:cipher_eye/services/firebase_service.dart';
import 'package:cipher_eye/services/expiry.dart';
import 'package:cipher_eye/services/haptics.dart';
import 'package:cipher_eye/services/history_service.dart';
import 'package:cipher_eye/services/person_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kreiseck_branding/kreiseck_branding.dart';

import '../models/item.dart';
import '../models/item_type.dart';
import '../providers/key_provider.dart';
import '../providers/items_provider.dart';
import '../providers/vaults_provider.dart';
import '../widgets/expiry_badge.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode focusNode = FocusNode();
  bool _showSearchBar = false;
  String? searchVal;

  @override
  void initState() {
    super.initState();
    // Reset any previously revealed password when the list (re)appears.
    ItemService.maskAll();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    focusNode.dispose();
    super.dispose();
  }

  bool get _hasKey => ref.read(keyProvider) != null;

  void _warnNoKey() {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text(
          'Kein Encryption-Key gesetzt — bitte in den Einstellungen eintragen.'),
      action: SnackBarAction(
        label: 'Einstellungen',
        onPressed: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const SettingsScreen())),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final hasKey = ref.watch(hasKeyProvider);
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.05),
        title: Stack(
          alignment: Alignment.center,
          children: [
            Opacity(
              opacity: _showSearchBar?1:0,
              child: TextField(
                focusNode: focusNode,
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Suchen',
                  border: InputBorder.none,
                ),
                onChanged: (val) {
                  setState(() {
                    searchVal = val;
                    if (searchVal != null && searchVal!.isEmpty) {
                      searchVal = null;
                    }
                    if (searchVal != null) {
                      _showSearchBar = true;
                    }
                  });
                },
                autofocus: true,
              ),
            ),
            Opacity(
              opacity: _showSearchBar?0:1,
              child: Text('Cipher Eye'),
            )
          ],
        ),
        actions: [
          if (_showSearchBar)
            IconButton(
              icon: Icon(Icons.clear),
              tooltip: 'Suche schließen',
              onPressed: () {
                setState(() {
                  _searchController.clear();
                  searchVal = null;
                  _showSearchBar = false;
                });
              },
            ),
          if (!_showSearchBar)
            IconButton(
              icon: Icon(Icons.search),
              tooltip: 'Suchen',
              onPressed: () {
                setState(() {
                  _showSearchBar = true;
                });
                FocusScope.of(context).requestFocus(focusNode);
              },
            ),
        ],
      ),
      body: Column(
        children: [
          if (!hasKey) _noKeyBanner(),
          if (hasKey) _expiryBanner(),
          if (ref.watch(vaultsProvider).isNotEmpty &&
              (_showSearchBar || ref.watch(sourceFilterProvider) != null))
            _sourceChips(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => ref.read(vaultsProvider.notifier).refresh(),
              child: passwords.isEmpty
                ? _emptyState()
                : NotificationListener<ScrollNotification>(
                    onNotification: (scrollNotification) {
                      if (!_showSearchBar && scrollNotification.metrics.pixels < -25) {
                        setState(() {
                          _showSearchBar = true;
                        });
                      }
                      return false;
                    },
                    child: ListView.separated(
                      controller: _scrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      itemCount: passwords.length,
                      itemBuilder: (ctx, i) => getSinglePasswordField(passwords[i]),
                      separatorBuilder: (ctx, i) => Divider(thickness: 1, color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2), height: 0,),
                    ),
                  ),
            ),
          ),
        ],
      ),
      drawer: _drawer(),
      floatingActionButton: _createNewFab(),
    );
  }

  List<Item> get passwords {
    final base = ref.watch(filteredItemsProvider);
    if (searchVal == null) {
      return base;
    }
    String specialChars = "+`-*/()&%§!?\$#@^_~|{}[]:;,<>.=";
    List<String> srcValList = searchVal!.split(' ').where((element) => element.isNotEmpty).toList();
    Map<String, List<Item>> resultMap = {};
    for (String srcVal in srcValList) {
      for (String c in specialChars.characters) {
        srcVal = srcVal.replaceAll(c, "").toUpperCase();
      }
      resultMap[srcVal] = base.where((element) {
        String website = (element.title ?? '').toUpperCase();
        String username = (element.username ?? '').toUpperCase();
        for (String c in specialChars.characters) {
          website = website.replaceAll(c, "");
          username = username.replaceAll(c, "");
        }
        return website.contains(srcVal) || username.contains(srcVal);
      }).toList();
    }
    List<Item> result = [];
    resultMap.forEach((key, value) {
      if (result.isEmpty) {
        result.addAll(value);
      } else {
        List<Item> toRemove = [];
        for (var element in result) {
          if (!value.contains(element)) {
            toRemove.add(element);
          }
        }
        for (var element in toRemove) {
          result.remove(element);
        }
      }
    });

    return result;
  }



  Widget _sourceChips() {
    final vaults = ref.watch(vaultsProvider);
    final current = ref.watch(sourceFilterProvider);
    Widget chip(String? value, String label, IconData icon) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(
            avatar: Icon(icon, size: 16),
            label: Text(label),
            selected: current == value,
            onSelected: (_) {
              Haptics.selection();
              if (value != null &&
                  value != kPersonalSource &&
                  ItemService.isLocked(value)) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text(
                        'Tresor gesperrt – bitte Encryption-Key prüfen')));
              }
              ref.read(sourceFilterProvider.notifier).state = value;
            },
          ),
        );
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          chip(null, 'Alle', Icons.all_inclusive),
          chip(kPersonalSource, 'Persönlich', Icons.person_outline),
          for (final v in vaults)
            chip(
                v.id,
                v.name,
                ItemService.isLocked(v.id)
                    ? Icons.lock_outline
                    : Icons.group_outlined),
        ],
      ),
    );
  }

  /// Documents/cards that expire soon or already did — and were not
  /// acknowledged with "OK" yet.
  List<(Item, ExpiryInfo)> _expiring() {
    final out = <(Item, ExpiryInfo)>[];
    for (final it in ref.watch(itemsProvider)) {
      if (it.type != ItemType.document && it.type != ItemType.card) continue;
      final info = Expiry.of(it);
      if (info.needsAttention && !Expiry.isAcked(it, info)) out.add((it, info));
    }
    out.sort((a, b) => (a.$2.days ?? 0).compareTo(b.$2.days ?? 0));
    return out;
  }

  Widget _expiryBanner() {
    final list = _expiring();
    if (list.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final worst = list.first.$2.level;
    final color = expiryColor(worst, scheme);
    final expired = list.where((e) => e.$2.level == ExpiryLevel.expired).length;
    final soon = list.length - expired;
    final parts = <String>[
      if (expired > 0) '$expired abgelaufen',
      if (soon > 0) '$soon ${soon == 1 ? 'läuft' : 'laufen'} bald ab',
    ];
    return Material(
      color: color.withValues(alpha: 0.12),
      child: ListTile(
        dense: true,
        leading: Icon(expiryIcon(worst), color: color),
        title: Text(
            list.length == 1
                ? '${list.first.$1.title ?? 'Dokument'}: ${list.first.$2.label}'
                : 'Dokumente/Karten: ${parts.join(', ')}',
            style: TextStyle(color: color, fontWeight: FontWeight.w600)),
        trailing: TextButton(
          onPressed: _showExpirySheet,
          child: const Text('Anzeigen'),
        ),
        onTap: _showExpirySheet,
      ),
    );
  }

  Future<void> _showExpirySheet() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => Consumer(builder: (ctx, ref, _) {
        final list = _expiring();
        final scheme = Theme.of(ctx).colorScheme;
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text('Ablaufende Dokumente & Karten',
                    style: Theme.of(ctx).textTheme.titleMedium),
              ),
              if (list.isEmpty)
                const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: Text('Alles erledigt'))),
              for (final (it, info) in list)
                ListTile(
                  leading: Icon(it.type.icon,
                      color: expiryColor(info.level, scheme)),
                  title: Text(it.title ?? it.type.label),
                  subtitle: ExpiryBadge(info),
                  trailing: TextButton(
                    onPressed: () async {
                      Haptics.selection();
                      await ref
                          .read(itemsProvider.notifier)
                          .acknowledgeExpiry(it, Expiry.ackHash(it, info.raw!));
                      if (mounted) setState(() {});
                    },
                    child: const Text('OK'),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _open(it);
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      }),
    );
    if (mounted) setState(() {});
  }

  Widget _vaultBadge(Item pass, ColorScheme scheme) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: scheme.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.group_outlined, size: 12, color: scheme.primary),
          const SizedBox(width: 4),
          Text(ItemService.vaultById(pass.vaultId)?.name ?? 'Tresor',
              style: TextStyle(
                  fontSize: 10,
                  color: scheme.primary,
                  fontWeight: FontWeight.bold)),
        ]),
      );

  Widget getSinglePasswordField(Item pass) {
    final scheme = Theme.of(context).colorScheme;
    final isPassword = pass.type == ItemType.password;
    final value = pass.isVisible ? pass.decrypted() : '••••••••••';
    final hasName = pass.title?.isNotEmpty ?? false;
    return ListTile(
      isThreeLine: isPassword,
      // Passwords: tap = copy, long-press = reveal, button opens details.
      // Drafts open their editor; other types open their detail screen.
      onTap: pass.isDraft || !isPassword
          ? () => _open(pass)
          : () => _copyFromList(pass),
      onLongPress:
          pass.isDraft || !isPassword ? null : () => _toggleReveal(pass),
      leading: CircleAvatar(
        backgroundColor: scheme.primary.withValues(alpha: 0.12),
        child: pass.isDraft
            ? Icon(Icons.edit_note, color: scheme.primary)
            : !isPassword
                ? Icon(pass.type.icon, color: scheme.primary)
                : Text(
                    hasName ? pass.title![0].toUpperCase() : '?',
                    style: TextStyle(
                        color: scheme.primary, fontWeight: FontWeight.bold),
                  ),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              hasName ? pass.title! : 'Unbenannter Entwurf',
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (pass.isDraft) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('ENTWURF',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.orange)),
            ),
          ],
          if (pass.vaultId != null) ...[
            const SizedBox(width: 8),
            _vaultBadge(pass, scheme),
          ],
        ],
      ),
      subtitle: isPassword
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if ((pass.username ?? '').isNotEmpty)
                  Text(pass.username!,
                      style: TextStyle(
                          color: scheme.onSurfaceVariant, fontSize: 12)),
                Text(value, style: const TextStyle(letterSpacing: 1.5)),
              ],
            )
          : Row(
              children: [
                Flexible(
                  child: Text(
                      pass.hasAttachments
                          ? '${pass.type.label} · ${pass.attachments.length} Seite${pass.attachments.length == 1 ? '' : 'n'}'
                          : pass.type.label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: scheme.onSurfaceVariant, fontSize: 12)),
                ),
                if (_hasKey && Expiry.of(pass).needsAttention) ...[
                  const SizedBox(width: 8),
                  ExpiryBadge(Expiry.of(pass), compact: true),
                ],
              ],
            ),
      trailing: IconButton(
        visualDensity: VisualDensity.compact,
        tooltip: pass.isDraft ? 'Entwurf bearbeiten' : 'Details öffnen',
        icon: Icon(
            pass.isDraft ? Icons.edit_note : Icons.chevron_right,
            size: 22),
        onPressed: () => _open(pass),
      ),
    );
  }

  void _open(Item pass) => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => pass.isDraft
              ? AddNewPasswordScreen(draft: pass)
              : pass.type == ItemType.password
                  ? PasswordDetailScreen(pass)
                  : ItemDetailScreen(pass),
        ),
      );

  void _toggleReveal(Item pass) {
    if (!pass.isVisible && !_hasKey) {
      _warnNoKey();
      return;
    }
    final revealing = !pass.isVisible;
    Haptics.selection();
    setState(() => pass.isVisible = !pass.isVisible);
    if (revealing) {
      HistoryService.saveViewHistory(pass.id!, vaultId: pass.vaultId);
      ItemService.incrementUsage(pass.id!, copy: false);
    }
  }

  Future<void> _copyFromList(Item pass) async {
    if (!_hasKey) {
      _warnNoKey();
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    await ClipboardService.copySensitive(pass.decrypted());
    HistoryService.saveCopyHistory(pass.id!, vaultId: pass.vaultId);
    ItemService.incrementUsage(pass.id!, copy: true);
    messenger.showSnackBar(const SnackBar(
      content: Text('Kopiert – wird in 30 s aus der Zwischenablage gelöscht'),
      duration: Duration(seconds: 2),
    ));
  }

  Widget _createNewFab() => FloatingActionButton(
    backgroundColor: Theme.of(context).colorScheme.primary,
    tooltip: 'Neu',
    child: const Icon(Icons.add),
    onPressed: () {
      if (!_hasKey) {
        _warnNoKey();
        return;
      }
      _showTypeChooser();
    },
  );

  Future<void> _showTypeChooser() async {
    final type = await showModalBottomSheet<ItemType>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('Was möchtest du speichern?',
                  style: Theme.of(ctx).textTheme.titleMedium),
            ),
            for (final t in ItemType.values)
              ListTile(
                leading: Icon(t.icon),
                title: Text(t.label),
                subtitle: _typeAvailable(t) ? null : const Text('Bald verfügbar'),
                enabled: _typeAvailable(t),
                onTap: () => Navigator.pop(ctx, t),
              ),
          ],
        ),
      ),
    );
    if (type == null || !mounted) return;
    Haptics.selection();
    final Widget screen = switch (type) {
      ItemType.password => const AddNewPasswordScreen(),
      ItemType.card => const CardEditorScreen(),
      ItemType.note => const NoteEditorScreen(),
      ItemType.document => const DocumentEditorScreen(),
      ItemType.file => const FileEditorScreen(),
    };
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  static bool _typeAvailable(ItemType t) => true;

  Widget _emptyState() {
    final searching = searchVal != null;
    final primary = Theme.of(context).colorScheme.primary;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.25),
        Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(searching ? Icons.search_off : Icons.lock_outline,
              size: 64, color: primary.withValues(alpha: 0.5)),
          const SizedBox(height: 16),
          Text(searching ? 'Keine Treffer' : 'Noch keine Einträge',
              style: Theme.of(context).textTheme.titleMedium),
          if (!searching) ...[
            const SizedBox(height: 8),
            Text('Tippe auf +, um dein erstes anzulegen',
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ),
        ),
      ],
    );
  }

  Widget _noKeyBanner() => Material(
    color: Theme.of(context).colorScheme.errorContainer,
    child: ListTile(
      leading: Icon(Icons.key_off,
          color: Theme.of(context).colorScheme.onErrorContainer),
      title: Text('Kein Encryption-Key gesetzt',
          style: TextStyle(
              color: Theme.of(context).colorScheme.onErrorContainer,
              fontWeight: FontWeight.bold)),
      subtitle: Text('Passwörter lassen sich nicht anzeigen.',
          style:
              TextStyle(color: Theme.of(context).colorScheme.onErrorContainer)),
      trailing: TextButton(
        onPressed: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const SettingsScreen())),
        child: const Text('Eintragen'),
      ),
    ),
  );

  Widget _drawer() => Drawer(
    key: _scaffoldKey,
    child: Column(
      children: [
        DrawerHeader(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary,
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              PersonService.person.name ?? '',
              style: const TextStyle(color: Colors.white, fontSize: 18),
            ),
          ),
        ),
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              ListTile(
                leading: const Icon(Icons.group_outlined),
                title: const Text('Tresore'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const VaultsScreen(),
                      ));
                },
              ),
              ListTile(
                leading: const Icon(Icons.settings_outlined),
                title: const Text('Einstellungen'),
                onTap: () {
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => SettingsScreen(),
                      ));
                },
              ),
              ListTile(
                title: const Text('Abmelden',
                    style: TextStyle(color: Colors.redAccent)),
                onTap: () {
                  FirebaseService.signOut();
                },
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: KreiseckLogo(
            height: 28,
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.white
                : null,
          ),
        ),
      ],
    ),
  );
}