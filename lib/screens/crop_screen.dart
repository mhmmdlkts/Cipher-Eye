import 'dart:typed_data';

import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/material.dart';

import '../services/image_pipeline.dart';

/// Rectangular crop + 90° rotation with aspect presets. Pops the cropped
/// JPEG bytes, or null when cancelled.
class CropScreen extends StatefulWidget {
  const CropScreen(this.image, {super.key});
  final Uint8List image;

  @override
  State<CropScreen> createState() => _CropScreenState();
}

class _CropScreenState extends State<CropScreen> {
  final _controller = CropController();
  late Uint8List _image = widget.image;
  double? _aspect;
  bool _busy = false;

  static const _presets = <String, double?>{
    'Frei': null,
    'Karte': 85.6 / 54.0,
    'A4': 210 / 297,
  };

  Future<void> _rotate() async {
    setState(() => _busy = true);
    final rotated = await ImagePipeline.rotate(_image, 1);
    if (!mounted) return;
    setState(() {
      _image = rotated;
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Zuschneiden'),
        actions: [
          IconButton(
              tooltip: 'Drehen',
              icon: const Icon(Icons.rotate_90_degrees_cw_outlined),
              onPressed: _busy ? null : _rotate),
          TextButton(
            onPressed: _busy
                ? null
                : () {
                    setState(() => _busy = true);
                    _controller.crop();
                  },
            child: const Text('Fertig',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Crop(
              key: ValueKey(_image.hashCode),
              image: _image,
              controller: _controller,
              aspectRatio: _aspect,
              baseColor: Colors.black,
              maskColor: Colors.black.withValues(alpha: 0.6),
              progressIndicator:
                  const Center(child: CircularProgressIndicator()),
              onCropped: (result) {
                if (!mounted) return;
                switch (result) {
                  case CropSuccess(:final croppedImage):
                    Navigator.pop(context, croppedImage);
                  case CropFailure():
                    setState(() => _busy = false);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Zuschneiden fehlgeschlagen')));
                }
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Wrap(
                spacing: 8,
                children: [
                  for (final e in _presets.entries)
                    ChoiceChip(
                      label: Text(e.key),
                      selected: _aspect == e.value,
                      selectedColor: scheme.primary,
                      onSelected: (_) {
                        setState(() => _aspect = e.value);
                        _controller.aspectRatio = e.value;
                      },
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
