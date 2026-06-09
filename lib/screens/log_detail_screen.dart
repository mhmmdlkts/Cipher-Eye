import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/history.dart';
import '../providers/place_provider.dart';

class LogDetailScreen extends ConsumerWidget {
  const LogDetailScreen(this.entry, {super.key});

  final History entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final dt = entry.timestamp?.toDate();
    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(title: Text(_label(entry.action))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 28),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [scheme.primary, scheme.secondary],
              ),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 34,
                  backgroundColor: Colors.white.withValues(alpha: 0.2),
                  child: Icon(_icon(entry.action), color: Colors.white, size: 34),
                ),
                const SizedBox(height: 14),
                Text(_label(entry.action),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold)),
                if (dt != null)
                  Text(_fmt(dt),
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9))),
              ],
            ),
          ),
          const SizedBox(height: 20),
          if (entry.location != null) _placeCard(context, ref, entry.location!),
          if (entry.ip != null)
            _infoCard(context, Icons.lan_outlined, 'IP-Adresse', entry.ip!),
          if (entry.deviceInfo != null)
            _infoCard(context, Icons.devices_outlined, 'Gerät',
                entry.deviceInfo!),
        ],
      ),
    );
  }

  Widget _placeCard(BuildContext context, WidgetRef ref, String coords) {
    final scheme = Theme.of(context).colorScheme;
    final placeAsync = ref.watch(placeProvider(coords));
    final city = placeAsync.maybeWhen(data: (s) => s, orElse: () => null);
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          ListTile(
            leading: Icon(Icons.place_outlined, color: scheme.primary),
            title: const Text('Standort'),
            subtitle: Text(city ?? 'Wird ermittelt …'),
          ),
          const Divider(height: 1),
          ListTile(
            leading: Icon(Icons.my_location_outlined, color: scheme.primary),
            title: const Text('Koordinaten'),
            subtitle: Text(coords),
          ),
        ],
      ),
    );
  }

  Widget _infoCard(
      BuildContext context, IconData icon, String title, String value) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        leading: Icon(icon, color: scheme.primary),
        title: Text(title),
        subtitle: Text(value),
      ),
    );
  }

  static IconData _icon(String? action) {
    switch (action) {
      case 'copy':
        return Icons.content_copy;
      case 'view':
        return Icons.visibility;
      case 'create':
        return Icons.add;
      case 'update':
        return Icons.autorenew;
      case 'delete':
        return Icons.delete_outline;
      case 'key':
        return Icons.vpn_key;
      case 'init':
        return Icons.login;
      default:
        return Icons.history;
    }
  }

  static String _label(String? action) {
    switch (action) {
      case 'copy':
        return 'Kopiert';
      case 'view':
        return 'Angesehen';
      case 'create':
        return 'Erstellt';
      case 'update':
        return 'Passwort neu gesetzt';
      case 'delete':
        return 'Gelöscht';
      case 'key':
        return 'Key angezeigt';
      case 'init':
        return 'App geöffnet';
      default:
        return action ?? 'Aktion';
    }
  }

  static String _fmt(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(dt.day)}.${two(dt.month)}.${dt.year}, ${two(dt.hour)}:${two(dt.minute)}';
  }
}
