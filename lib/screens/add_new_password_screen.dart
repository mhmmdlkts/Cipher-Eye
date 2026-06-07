import 'package:cipher_eye/models/password.dart';
import 'package:cipher_eye/services/password_generator.dart';
import 'package:cipher_eye/services/person_service.dart';
import 'package:flutter/material.dart';

import '../services/clipboard_service.dart';
import '../services/password_service.dart';

class AddNewPasswordScreen extends StatefulWidget {
  const AddNewPasswordScreen({super.key});

  @override
  State<AddNewPasswordScreen> createState() => _AddNewPasswordScreenState();
}

class _AddNewPasswordScreenState extends State<AddNewPasswordScreen> {

  final TextEditingController _websiteController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  List<String> get usernames => PersonService.person.usernames;

  bool isLoading = false;
  bool isFavorite = false;
  bool includeSpecialChars = true;
  int passwordLength = 24;

  @override
  void initState() {
    super.initState();
    _usernameController.text = usernames.isNotEmpty ? usernames.first : '';
    _passwordController.text = PasswordGenerator.generatePassword(
        length: passwordLength,
        incSpecialChars: includeSpecialChars
    );
  }

  @override
  void dispose() {
    _websiteController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: const Text('Add New Password'),
      ),
      body: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8.0,
                    runSpacing: 4.0,
                    children: List<Widget>.generate(usernames.length, (int index) {
                      return InputChip(
                        onPressed: isLoading?null:() {
                          setState(() {
                            _usernameController.text = usernames[index];
                          });
                        },
                        label: Text(usernames[index]),
                      );
                    }),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _usernameController,
                    decoration: InputDecoration(
                      labelText: 'Username',
                      hintText: 'Enter username',
                      enabled: !isLoading
                    ),
                    validator: (String? value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter a username';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _websiteController,
                    decoration: InputDecoration(
                      labelText: 'Website',
                      hintText: 'Enter website',
                        enabled: !isLoading
                    ),
                    validator: (String? value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter a website';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _passwordController,
                    decoration: InputDecoration(
                        labelText: 'Password',
                        hintText: 'Enter password',
                        enabled: !isLoading
                    ),
                    validator: (String? value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter a password';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    title: const Text('Sonderzeichen einschließen'),
                    value: includeSpecialChars,
                    onChanged: isLoading ? null : (val) {
                      setState(() {
                        includeSpecialChars = val;
                        _passwordController.text = PasswordGenerator.generatePassword(
                          length: passwordLength.toInt(),
                          incSpecialChars: includeSpecialChars
                        );
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Passwortlänge:'),
                      Slider(
                        value: passwordLength.toDouble(),
                        min: 8,
                        max: 32,
                        divisions: 24,
                        label: passwordLength.toInt().toString(),
                        onChanged: isLoading ? null : (val) {
                          int newLength = val.toInt();
                          if (passwordLength == newLength) {
                            return;
                          }
                          setState(() {
                            passwordLength = newLength;
                            _passwordController.text = PasswordGenerator.generatePassword(
                              length: newLength,
                              incSpecialChars: includeSpecialChars
                            );
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Checkbox(
                          value: isFavorite,
                          onChanged: (val) {
                            setState(() {
                              isFavorite = val??false;
                            });
                          }
                      ),
                      const Text('Favorite'),
                    ],
                  )
                ],
              ),
            ),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: isLoading ? null : () async {
                  if (!_formKey.currentState!.validate()) {
                    return;
                  }
                  setState(() => isLoading = true);
                  final messenger = ScaffoldMessenger.of(context);
                  final navigator = Navigator.of(context);
                  try {
                    final password = Password.create(
                      website: _websiteController.text,
                      username: _usernameController.text,
                      plaintText: _passwordController.text,
                      isFavorite: isFavorite,
                    );
                    await PasswordService.addNewPassword(password);
                    await ClipboardService.copySensitive(_passwordController.text);
                    messenger.showSnackBar(const SnackBar(
                      content: Text('Gespeichert & kopiert (Zwischenablage wird in 30 s geleert)'),
                      duration: Duration(seconds: 2),
                    ));
                    navigator.pop();
                  } catch (e) {
                    if (mounted) {
                      setState(() => isLoading = false);
                    }
                    messenger.showSnackBar(const SnackBar(
                      content: Text('Speichern fehlgeschlagen. Ist dein Encryption-Key gesetzt?'),
                      backgroundColor: Colors.red,
                    ));
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.all(40),
                  child: isLoading?const CircularProgressIndicator(color: Colors.white):const Text('Save'),
                ),
              ),
            ),
          ],
        ),
      )
    );
  }
}
