import 'package:cipher_eye/screens/add_new_password_screen.dart';
import 'package:cipher_eye/screens/settings_screen.dart';
import 'package:cipher_eye/services/firebase_service.dart';
import 'package:cipher_eye/services/password_service.dart';
import 'package:cipher_eye/services/person_service.dart';
import 'package:cipher_eye/services/secure_storage_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/password.dart';

class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
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
                  hintStyle: TextStyle(color: Colors.white),
                  border: InputBorder.none,
                ),
                style: TextStyle(color: Colors.white),
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
              onPressed: () {
                setState(() {
                  _showSearchBar = true;
                });
                FocusScope.of(context).requestFocus(focusNode);
              },
            ),
        ],
      ),
      body: NotificationListener<ScrollNotification>(
        onNotification: (scrollNotification) {
          if (!_showSearchBar && scrollNotification.metrics.pixels < -25) {
            setState(() {
              _showSearchBar = true;
            });
          }
          return false;
        },
        child: ListView.builder(
          controller: _scrollController,
          itemCount: passwords.length,
          itemBuilder: (ctx, i) => getSinglePasswordField(passwords[i]),
        ),
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
        result.forEach((element) {
          if (!value.contains(element)) {
            toRemove.add(element);
          }
        });
        toRemove.forEach((element) {
          result.remove(element);
        });
      }
    });

    return result;
  }



  Widget getSinglePasswordField(Password pass) {
    String val = pass.isVisible ? pass.getPlainText() : List.filled(16, "•").join();
    return Card(
      child: InkWell(
        onLongPress: editMode?null:() {
          if (editMode) {

            return;
          }
          setState(() {
            pass.isVisible = !pass.isVisible;
          });
        },
        onTap: editMode?null:() async {
          if (editMode) {
            return;
          }
          await Clipboard.setData(ClipboardData(text: pass.getPlainText()));
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Password copied to clipboard!'),
              duration: Duration(seconds: 1),
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
              Text(pass.website!),
              Text(val)
            ],
          ),
          subtitle: Text(pass.username!),
          trailing: editMode?IconButton(
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
          ):null
        ),
      ),
    );
  }

  Widget _createNewFab() => FloatingActionButton(
    child: Icon(Icons.add),
    onPressed: () async {
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

  Widget _drawer() => Drawer(
    key: _scaffoldKey,
    child: ListView(
      padding: EdgeInsets.zero,
      children: [
        DrawerHeader(
          decoration: BoxDecoration(
            color: Color(0xff32614f),
          ),
          child: Text(PersonService.person?.name??'', style: TextStyle(color: Colors.white)),
        ),
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
                )
            );
          },
        ),
        ListTile(
          title: const Text('Sign Out', style: TextStyle(color: Colors.redAccent),),
          onTap: () {
            FirebaseService.signOut();
          },
        ),
      ],
    ),
  );
}
