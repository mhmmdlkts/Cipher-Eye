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

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    List<Password> passwords = PasswordService.newPasswords;
    return Scaffold(
      appBar: AppBar(
        title: Text('Cipher Eye'),
      ),
      body: ListView.builder(
        itemCount: passwords.length,
        itemBuilder: (ctx, i) => getSinglePasswordField(passwords[i]),
      ),
      drawer: Drawer(
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
      ),
      floatingActionButton: FloatingActionButton(
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
      ),
    );
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
}
