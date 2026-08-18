import 'package:flutter/material.dart';

import 'app_text_field.dart';

/// Single-field prompt dialog; owns its controller so it is disposed with the
/// route, never while the closing animation still runs.
Future<String?> showTextPrompt(
  BuildContext context, {
  required String title,
  required String label,
  String? hint,
  String initial = '',
  String confirm = 'OK',
  IconData? icon,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _TextPromptDialog(
        title: title,
        label: label,
        hint: hint,
        initial: initial,
        confirm: confirm,
        icon: icon),
  );
}

class _TextPromptDialog extends StatefulWidget {
  const _TextPromptDialog({
    required this.title,
    required this.label,
    required this.initial,
    required this.confirm,
    this.hint,
    this.icon,
  });
  final String title, label, initial, confirm;
  final String? hint;
  final IconData? icon;

  @override
  State<_TextPromptDialog> createState() => _TextPromptDialogState();
}

class _TextPromptDialogState extends State<_TextPromptDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: AppTextField(
        controller: _controller,
        label: widget.label,
        hint: widget.hint,
        prefixIcon: widget.icon,
        autofocus: true,
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Abbrechen')),
        ElevatedButton(
            onPressed: () => Navigator.pop(context, _controller.text),
            child: Text(widget.confirm)),
      ],
    );
  }
}
