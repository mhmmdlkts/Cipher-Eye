import 'package:cipher_eye/models/password.dart';
import 'package:cipher_eye/services/password_generator.dart';
import 'package:cipher_eye/services/person_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/password_service.dart';

class AddNewPasswordScreen extends StatefulWidget {
  const AddNewPasswordScreen({Key? key}) : super(key: key);

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

  @override
  void initState() {
    super.initState();
    _usernameController.text = usernames.first;
    _passwordController.text = PasswordGenerator.generatePassword();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                  Checkbox(
                      value: isFavorite,
                      onChanged: (val) {
                        setState(() {
                          isFavorite = val??false;
                        });
                      }
                  ),
                ],
              ),
            ),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  if (_formKey.currentState!.validate()) {
                    setState(() {
                      isLoading = true;
                    });
                    Password password = Password.create(
                      website: _websiteController.text,
                      username: _usernameController.text,
                      plaintText: _passwordController.text,
                      isFavorite: isFavorite
                    );
                    await PasswordService.addNewPassword(password);
                    await Clipboard.setData(ClipboardData(text: _passwordController.text));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Password copied to clipboard!'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  }
                  if (mounted) {
                    Navigator.pop(context);
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
