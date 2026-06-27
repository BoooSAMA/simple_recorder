import 'package:flutter/material.dart';

class AppEmptyWidget extends StatelessWidget {
  final Function()? onRefresh;
  const AppEmptyWidget({this.onRefresh, super.key});

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
              Icon(Icons.inbox_outlined,
                  size: 80, color: Theme.of(context).disabledColor),
              const SizedBox(height: 16),
              Text("这里什么都没有",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 12, color: Theme.of(context).disabledColor)),
            ],
          ),
        ),
      ),
    );
  }
}
