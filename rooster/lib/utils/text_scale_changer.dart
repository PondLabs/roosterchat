import 'dart:async';

import 'package:rooster/main.dart';
import 'package:flutter/material.dart';

class TextScaleChanger extends StatefulWidget {
  const TextScaleChanger({required this.child, super.key});
  final Widget child;

  @override
  State<TextScaleChanger> createState() => _TextScaleChangerState();
}

class _TextScaleChangerState extends State<TextScaleChanger> {
  StreamSubscription<double>? _textScaleSubscription;

  @override
  void initState() {
    super.initState();
    _textScaleSubscription = preferences.textScale.onChanged.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _textScaleSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (preferences.textScale.value == 1.0) {
      return widget.child;
    }

    return MediaQuery(
        data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(preferences.textScale.value)),
        child: widget.child);
  }
}
