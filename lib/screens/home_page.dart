import 'package:cipher_eye/screens/add_new_password_screen.dart';
import 'package:cipher_eye/screens/password_detail_screen.dart';
import 'package:cipher_eye/screens/settings_screen.dart';
import 'package:cipher_eye/services/clipboard_service.dart';
import 'package:cipher_eye/services/firebase_service.dart';
import 'package:cipher_eye/services/history_service.dart';
import 'package:cipher_eye/services/password_service.dart';
import 'package:cipher_eye/services/person_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kreiseck_branding/kreiseck_branding.dart';

import '../models/password.dart';
import '../providers/key_provider.dart';
import '../providers/passwords_provider.dart';

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
    PasswordService.maskAll();
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
          Expanded(
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
                      itemCount: passwords.length,
                      itemBuilder: (ctx, i) => getSinglePasswordField(passwords[i]),
                      separatorBuilder: (ctx, i) => Divider(thickness: 1, color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2), height: 0,),
                    ),
                  ),
          ),
        ],
      ),
      drawer: _drawer(),
      floatingActionButton: _createNewFab(),
    );
  }

  List<Password> get passwords {
    final base = ref.watch(passwordsProvider);
    if (searchVal == null) {
      return base;
    }
    String specialChars = "+`-*/()&%§!?\$#@^_~|{}[]:;,<>.=";
    List<String> srcValList = searchVal!.split(' ').where((element) => element.isNotEmpty).toList();
    Map<String, List<Password>> resultMap = {};
    for (String srcVal in srcValList) {
      for (String c in specialChars.characters) {
        srcVal = srcVal.replaceAll(c, "").toUpperCase();
      }
      resultMap[srcVal] = base.where((element) {
        if (element.website == null || element.username == null) {
          return true;
        }
        String website = element.website!.toUpperCase();
        String username = element.username!.toUpperCase();
        for (String c in specialChars.characters) {
          website = website.replaceAll(c, "");
          username = username.replaceAll(c, "");
        }
        return website.contains(srcVal) || username.contains(srcVal);
      }).toList();
    }
    List<Password> result = [];
    resultMap.forEach((key, value) {
      if (result.isEmpty) {
        result.addAll(value);
      } else {
        List<Password> toRemove = [];
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



  Widget getSinglePasswordField(Password pass) {
    final scheme = Theme.of(context).colorScheme;
    final value = pass.isVisible ? pass.decrypted() : '••••••••••';
    final hasName = pass.website?.isNotEmpty ?? false;
    return ListTile(
      isThreeLine: true,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => pass.isDraft
              ? AddNewPasswordScreen(draft: pass)
              : PasswordDetailScreen(pass),
        ),
      ),
      leading: CircleAvatar(
        backgroundColor: scheme.primary.withValues(alpha: 0.12),
        child: pass.isDraft
            ? Icon(Icons.edit_note, color: scheme.primary)
            : Text(
                hasName ? pass.website![0].toUpperCase() : '?',
                style: TextStyle(
                    color: scheme.primary, fontWeight: FontWeight.bold),
              ),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              hasName ? pass.website! : 'Unbenannter Entwurf',
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
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if ((pass.username ?? '').isNotEmpty)
            Text(pass.username!,
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
          Text(value, style: const TextStyle(letterSpacing: 1.5)),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: pass.isVisible ? 'Verbergen' : 'Anzeigen',
            icon: Icon(
                pass.isVisible ? Icons.visibility : Icons.visibility_off,
                size: 20),
            onPressed: () => _toggleReveal(pass),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Kopieren',
            icon: const Icon(Icons.content_copy, size: 18),
            onPressed: () => _copyFromList(pass),
          ),
        ],
      ),
    );
  }

  void _toggleReveal(Password pass) {
    if (!pass.isVisible && !_hasKey) {
      _warnNoKey();
      return;
    }
    final revealing = !pass.isVisible;
    setState(() => pass.isVisible = !pass.isVisible);
    if (revealing) {
      HistoryService.saveViewHistory(pass.id!);
      PasswordService.incrementUsage(pass.id!, copy: false);
    }
  }

  Future<void> _copyFromList(Password pass) async {
    if (!_hasKey) {
      _warnNoKey();
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    await ClipboardService.copySensitive(pass.decrypted());
    HistoryService.saveCopyHistory(pass.id!);
    PasswordService.incrementUsage(pass.id!, copy: true);
    messenger.showSnackBar(const SnackBar(
      content: Text('Kopiert – wird in 30 s aus der Zwischenablage gelöscht'),
      duration: Duration(seconds: 2),
    ));
  }

  Widget _createNewFab() => FloatingActionButton(
    backgroundColor: Theme.of(context).colorScheme.primary,
    child: Icon(Icons.add),
    onPressed: () async {
      if (!_hasKey) {
        _warnNoKey();
        return;
      }
      await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => AddNewPasswordScreen(),
          )
      );
    },
  );

  Widget _emptyState() {
    final searching = searchVal != null;
    final primary = Theme.of(context).colorScheme.primary;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(searching ? Icons.search_off : Icons.lock_outline,
              size: 64, color: primary.withValues(alpha: 0.5)),
          const SizedBox(height: 16),
          Text(searching ? 'Keine Treffer' : 'Noch keine Passwörter',
              style: Theme.of(context).textTheme.titleMedium),
          if (!searching) ...[
            const SizedBox(height: 8),
            Text('Tippe auf +, um dein erstes anzulegen',
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ),
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