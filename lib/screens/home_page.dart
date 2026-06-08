import 'dart:async';

import 'package:cipher_eye/screens/add_new_password_screen.dart';
import 'package:cipher_eye/screens/settings_screen.dart';
import 'package:cipher_eye/services/clipboard_service.dart';
import 'package:cipher_eye/services/firebase_service.dart';
import 'package:cipher_eye/services/password_service.dart';
import 'package:cipher_eye/services/person_service.dart';
import 'package:cipher_eye/services/secure_storage_service.dart';
import 'package:flutter/material.dart';
import 'package:kreiseck_branding/kreiseck_branding.dart';

import '../models/password.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode focusNode = FocusNode();
  bool _showSearchBar = false;
  bool editMode = false;
  String? searchVal;

  static const Duration _remaskAfter = Duration(seconds: 20);
  final Map<String, Timer> _remaskTimers = {};

  @override
  initState() {
    super.initState();
    // Whenever the list (re)appears — cold start, after unlock, returning from
    // another screen — start with every password masked.
    PasswordService.maskAll();
  }

  @override
  void dispose() {
    for (final t in _remaskTimers.values) {
      t.cancel();
    }
    _remaskTimers.clear();
    _searchController.dispose();
    _scrollController.dispose();
    focusNode.dispose();
    super.dispose();
  }

  /// Auto-hides a revealed password again after a short delay, so it is never
  /// left visible on screen indefinitely.
  void _scheduleRemask(Password pass) {
    _remaskTimers.remove(pass.id)?.cancel();
    if (pass.isVisible) {
      _remaskTimers[pass.id!] = Timer(_remaskAfter, () {
        _remaskTimers.remove(pass.id);
        if (mounted) {
          setState(() => pass.isVisible = false);
        }
      });
    }
  }

  bool get _hasKey => SecureStorageService.key != null;

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
                  hintText: 'Search',
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
          if (!_hasKey) _noKeyBanner(),
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
      floatingActionButton: editMode?_closeEditModeFab():_createNewFab(),
    );
  }

  List<Password> get passwords {
    if (searchVal == null) {
      return PasswordService.newPasswords;
    }
    String specialChars = "+`-*/()&%§!?\$#@^_~|{}[]:;,<>.=";
    List<String> srcValList = searchVal!.split(' ').where((element) => element.isNotEmpty).toList();
    Map<String, List<Password>> resultMap = {};
    for (String srcVal in srcValList) {
      for (String c in specialChars.characters) {
        srcVal = srcVal.replaceAll(c, "").toUpperCase();
      }
      resultMap[srcVal] = PasswordService.newPasswords.where((element) {
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



  void _toggleReveal(Password pass) {
    if (!pass.isVisible && !_hasKey) {
      _warnNoKey();
      return;
    }
    setState(() => pass.isVisible = !pass.isVisible);
    _scheduleRemask(pass);
  }

  Widget getSinglePasswordField(Password pass) {
    String val = pass.isVisible ? pass.getPlainText() : List.filled(16, "•").join();
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onLongPress: editMode ? null : () => _toggleReveal(pass),
        onTap: editMode?null:() async {
          if (editMode) {
            return;
          }
          if (!_hasKey) {
            _warnNoKey();
            return;
          }
          final messenger = ScaffoldMessenger.of(context);
          await ClipboardService.copySensitive(pass.getPlainText());
          messenger.showSnackBar(
            const SnackBar(
              content: Text('Kopiert – wird in 30 s aus der Zwischenablage gelöscht'),
              duration: Duration(seconds: 2),
            ),
          );
        },
        child: ListTile(
          /*leading: CircleAvatar(
            backgroundImage: NetworkImage('https://your_image_provider.com/${pass.website}.png'),
            backgroundColor: Colors.transparent,
          ),*/
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(pass.website ?? ''),
                Row(
                  children: [
                    Expanded(child: Text(val)),
                    if (!editMode)
                      InkWell(
                        onTap: () => _toggleReveal(pass),
                        customBorder: const CircleBorder(),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(
                            pass.isVisible
                                ? Icons.visibility
                                : Icons.visibility_off,
                            size: 18,
                            semanticLabel:
                                pass.isVisible ? 'Verbergen' : 'Anzeigen',
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
            subtitle: Text(pass.username!),
            trailing: editMode?IconButton(
              tooltip: 'Löschen',
              onPressed: () async {
                showDialog(
                    context: context,
                    builder: (context) {
                      return AlertDialog(
                        title: Text('Delete Password'),
                        content: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('Do you really want to delete this password?'),
                            Container(height: 10),
                            Text(pass.website!, style: TextStyle(fontWeight: FontWeight.bold),),
                          ],
                        ),
                        actions: [
                          TextButton(
                            onPressed: () {
                              Navigator.pop(context);
                            },
                            child: Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () async {
                              Navigator.pop(context);
                              await PasswordService.deletePassword(pass);
                              setState(() {});
                            },
                            child: Text('Delete'),
                          ),
                        ],
                      );
                    }
                );
              },
              icon: const Icon(Icons.delete, color: Colors.red, size: 20),
            ):(pass.isFavorite?const Icon(Icons.star, color: Colors.yellow, size: 20):null)
        ),
      ),
    );
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
      setState(() {});
    },
  );

  Widget _closeEditModeFab() => FloatingActionButton(
    child: Icon(Icons.close),
    onPressed: () async {
      setState(() {
        editMode = false;
      });
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
              if (!editMode)
                ListTile(
                  title: const Text('Edit'),
                  onTap: () {
                    setState(() {
                      editMode = true;
                    });
                  },
                ),
              ListTile(
                title: const Text('Settings'),
                onTap: () {
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => SettingsScreen(),
                      ));
                },
              ),
              ListTile(
                title: const Text('Sign Out',
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