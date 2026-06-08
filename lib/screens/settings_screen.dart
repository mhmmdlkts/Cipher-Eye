import 'package:cipher_eye/services/history_service.dart';
import 'package:cipher_eye/services/secure_storage_service.dart';
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _keyController = TextEditingController();
  final LocalAuthentication _localAuth = LocalAuthentication();
  bool isLoading = false;
  bool isVisible = false;

  /// Requires device auth before a sensitive key action. If the device has no
  /// lock at all, allows it (can't enforce what doesn't exist).
  Future<bool> _reauth(String reason) async {
    try {
      if (!await _localAuth.isDeviceSupported()) return true;
      return await _localAuth.authenticate(
        localizedReason: reason,
        biometricOnly: false,
        persistAcrossBackgrounding: true,
        sensitiveTransaction: true,
      );
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  String? get key => SecureStorageService.key;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Enter Encryption Key')),
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.all(16),
            child: key!=null?keyPlaceHolder():TextField(
              controller: _keyController,
              decoration: InputDecoration(
                labelText: 'Encryption Key',
                hintText: 'Enter your 32-character encryption key',
              ),
              maxLength: 32,
              onChanged: (val) {
                setState(() {
                });
              },
            ),
          ),
          SizedBox(height: 16),
          Expanded(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: !isValid||isLoading?null:() async {
                    final key = _keyController.text.trim();
                    if (key.length != 32) return;
                    setState(() => isLoading = true);
                    await SecureStorageService.putKey(key);
                    if (!mounted) return;
                    _keyController.clear();
                    setState(() => isLoading = false);
                  },
                  child: Padding(
                    padding: EdgeInsets.all(40),
                    child: isLoading?CircularProgressIndicator():Text('Save'),
                  ),
                ),
              ),
            ),
          ),
        ],
      )
    );
  }

  Widget keyPlaceHolder() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Current Encryption Key:',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                isVisible?(key??''):List.filled(key?.length ?? 32, "*").join(),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              onPressed: () async {
                if (!isVisible &&
                    !await _reauth('Authentifiziere dich, um den Key anzuzeigen')) {
                  return;
                }
                await HistoryService.saveShowKey();
                if (mounted) {
                  setState(() => isVisible = !isVisible);
                }
              },
              icon: Icon(isVisible?Icons.visibility:Icons.visibility_off),
            ),
            IconButton(
              onPressed: () async {
                if (!await _reauth('Authentifiziere dich, um den Key zu löschen')) {
                  return;
                }
                if (!mounted) return;
                bool? shouldDelete = await showDialog<bool>(
                  context: context,
                  builder: (BuildContext context) {
                    return AlertDialog(
                      title: Text('Are you sure?'),
                      content: Text('Do you want to delete the current encryption key?'),
                      actions: [
                        TextButton(
                          onPressed: () {
                            Navigator.of(context).pop(true);
                          },
                          child: Text('Yes'),
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.of(context).pop(false);
                          },
                          child: Text('No'),
                        ),
                      ],
                    );
                  },
                );

                if (shouldDelete == true) {
                  await SecureStorageService.removeKey();
                  if (mounted) {
                    setState(() => _keyController.clear());
                  }
                }
              },
              icon: Icon(Icons.delete, color: Colors.red),
            ),
          ],
        ),
      ],
    );
  }

  bool get isValid => _keyController.text.length == 32 && _keyController.text != key;

}
