// One-off helper to create an ISOLATED test account in the cipher-eye project
// and seed it with legacy (v1) password docs — i.e. exactly what the old app
// wrote: AES-SIC with an all-zeros IV, and NO `iv` / `v` fields. Running the new
// app against this account then exercises the real migration against the real
// deployed Firestore rules, without touching any real user data.
//
// Idempotent: deterministic doc ids + PATCH, so re-running resets the entries
// back to v1 (handy for repeating the migration test).
//
//   dart run tool/seed_test_account.dart
//
// NOTE: throwaway test data only. Delete the test user in the Firebase console
// when done.

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart';

const String apiKey = 'AIzaSyDp1tCNUMK_wCNMXfAP1CgFlmayTXi3ODY'; // web API key
const String projectId = 'cipher-eye';

const String testEmail = 'migration.test.001@example.com';
const String testPassword = 'Migrate!Test#2026xZ';
const String testKey = 'TestKey_0123456789_abcdefghijkl!'; // exactly 32 chars

// The legacy entries to seed (plaintext is what you should see on reveal).
const List<Map<String, String>> samples = [
  {'website': 'github.com', 'username': 'testuser', 'plain': 'GitHubPass123!'},
  {'website': 'gmail.com', 'username': 'testuser', 'plain': 'GmailSecret456@'},
  {'website': 'bank.example', 'username': 'testuser', 'plain': r'B@nk-Pass-789'},
];

String v1Encode(String plain) {
  // Reproduces the original scheme: AES default mode (SIC) + PKCS7 + zero IV.
  final encrypter = Encrypter(AES(Key.fromUtf8(testKey)));
  return encrypter.encrypt(plain, iv: IV.allZerosOfLength(16)).base64;
}

String purposeId(String website, String username) =>
    sha256.convert(utf8.encode(website + username)).toString();

Future<Map<String, dynamic>> _send(
    String method, Uri url, Map<String, dynamic> body,
    {String? bearer}) async {
  final client = HttpClient();
  final req = await client.openUrl(method, url);
  req.headers.contentType = ContentType.json;
  if (bearer != null) req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearer');
  req.add(utf8.encode(jsonEncode(body)));
  final resp = await req.close();
  final text = await resp.transform(utf8.decoder).join();
  client.close();
  if (resp.statusCode >= 300) {
    throw 'HTTP ${resp.statusCode} on $method $url\n$text';
  }
  return text.isEmpty ? {} : jsonDecode(text) as Map<String, dynamic>;
}

Future<Map<String, dynamic>> _auth(String action) => _send(
      'POST',
      Uri.parse(
          'https://identitytoolkit.googleapis.com/v1/accounts:$action?key=$apiKey'),
      {'email': testEmail, 'password': testPassword, 'returnSecureToken': true},
    );

Future<void> main() async {
  if (testKey.length != 32) {
    throw 'testKey must be 32 chars, got ${testKey.length}';
  }

  // 1) Create the test user, or sign in if it already exists.
  Map<String, dynamic> session;
  try {
    session = await _auth('signUp');
    stdout.writeln('Created test user.');
  } catch (e) {
    if (e.toString().contains('EMAIL_EXISTS')) {
      session = await _auth('signInWithPassword');
      stdout.writeln('Test user already existed — signed in.');
    } else {
      rethrow;
    }
  }
  final String idToken = session['idToken'] as String;
  final String uid = session['localId'] as String;

  final base =
      'https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents';

  // 2) Profile doc WITHOUT securityVersion -> app treats it as v1 -> migration fires.
  await _send(
    'PATCH',
    Uri.parse('$base/users/$uid'),
    {
      'fields': {
        'name': {'stringValue': 'Migration Test'},
        'usernames': {
          'arrayValue': {
            'values': [
              {'stringValue': 'testuser'}
            ]
          }
        },
      }
    },
    bearer: idToken,
  );
  stdout.writeln('Seeded profile doc (no securityVersion).');

  // 3) Legacy password docs (no iv / no v) with deterministic ids.
  for (var i = 0; i < samples.length; i++) {
    final s = samples[i];
    await _send(
      'PATCH',
      Uri.parse('$base/users/$uid/passwords/seed-${i + 1}'),
      {
        'fields': {
          'value': {'stringValue': v1Encode(s['plain']!)},
          'website': {'stringValue': s['website']},
          'username': {'stringValue': s['username']},
          'purposeId': {
            'stringValue': purposeId(s['website']!, s['username']!)
          },
          'timestamp': {
            'timestampValue':
                '2024-01-0${i + 1}T12:00:00Z'
          },
          'isFavorite': {'booleanValue': false},
        }
      },
      bearer: idToken,
    );
    stdout.writeln('Seeded v1 entry seed-${i + 1}: ${s['website']}');
  }

  stdout.writeln('\nDone. Test account uid=$uid');
  stdout.writeln('Login:  $testEmail / $testPassword');
  stdout.writeln('Key:    $testKey');
}
