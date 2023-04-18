import 'package:cipher_eye/services/history_service.dart';
import 'package:cipher_eye/services/secure_storage_service.dart';
import 'package:flutter/material.dart';

class SettingsScreen extends StatefulWidget {
  @override
  _SettingsScreenState createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _keyController = TextEditingController();
  bool isLoading = false;
  bool isVisible = false;

  @override
  void initState() {
    super.initState();
  }

  String? get key => SecureStorageService.key;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Enter Encryption Key')),
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
                    String key = _keyController.text.trim();
                    if (key.length == 32) {
                      setState(() {
                        isLoading = true;
                      });
                      await SecureStorageService.putKey(key);
                      _keyController.clear();
                      setState(() {
                        isLoading = false;
                      });
                    } else {
                      // Show an error message
                    }
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
                await HistoryService.saveShowKey();
                setState(() {
                  isVisible = !isVisible;
                });
              },
              icon: Icon(isVisible?Icons.visibility:Icons.visibility_off),
            ),
            IconButton(
              onPressed: () async {
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
                  setState(() {
                    _keyController.clear();
                    setState(() {});
                  });
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
