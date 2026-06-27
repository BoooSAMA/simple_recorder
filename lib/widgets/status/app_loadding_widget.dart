import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class AppLoaddingWidget extends StatelessWidget {
  const AppLoaddingWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Theme.of(context).cardColor,
          boxShadow: Get.isDarkMode
              ? []
              : [
                  BoxShadow(
                    blurRadius: 4,
                    color: Colors.grey.withAlpha(50),
                  )
                ],
        ),
        child: const CupertinoActivityIndicator(radius: 10),
      ),
    );
  }
}
