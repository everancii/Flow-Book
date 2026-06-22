import 'package:flutter/material.dart';

class GlobalLoadingOverlay extends StatelessWidget {
  final bool isLoading;
  final Widget child;

  const GlobalLoadingOverlay({
    super.key,
    required this.isLoading,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return child;
  }
}
