import 'package:flutter/material.dart';

class AppErrorWidget extends StatelessWidget {
  final Function()? onRefresh;
  final String errorMsg;
  const AppErrorWidget({this.errorMsg = "", this.onRefresh, super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GestureDetector(
        onTap: () => onRefresh?.call(),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline,
                  size: 80, color: Theme.of(context).colorScheme.error),
              const SizedBox(height: 16),
              Text(
                "$errorMsg\r\n点击刷新",
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 12, color: Theme.of(context).disabledColor),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
