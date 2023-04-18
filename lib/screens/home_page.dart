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
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _showSearchBar = false;
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
      floatingActionButton: _fab(),
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
        srcVal = srcVal.replaceAll(c, "");
      }
      resultMap[srcVal] = PasswordService.newPasswords.where((element) {
        if (element.website == null || element.username == null) {
          return true;
        }
        String website = element.website!;
        String username = element.username!;
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
        onLongPress: () {
          setState(() {
            pass.isVisible = !pass.isVisible;
          });
        },
        onTap: () async {
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
          /*trailing: IconButton(
            onPressed: () { },
            icon: Icon(Icons.more_horiz, size: 20),
          )*/
        ),
      ),
    );
  }

  Widget _fab() => FloatingActionButton(
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

  Widget _drawer() => Drawer(
    child: ListView(
      padding: EdgeInsets.zero,
      children: [
        DrawerHeader(
          decoration: BoxDecoration(
            color: Color(0xff32614f),
          ),
          child: Text(PersonService.person?.name??'', style: TextStyle(color: Colors.white)),
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
