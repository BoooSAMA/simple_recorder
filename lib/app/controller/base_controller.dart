import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:simple_recorder/app/log.dart';

class BaseController extends GetxController {
  final pageLoadding = false.obs;
  var loadding = false;
  final pageEmpty = false.obs;
  final pageError = false.obs;
  final errorMsg = "".obs;

  void handleError(Object exception, {bool showPageError = false}) {
    Log.e(exception.toString());
    var msg = exceptionToString(exception);
    if (showPageError) {
      pageError.value = true;
      errorMsg.value = msg;
    } else {
      SmartDialog.showToast(msg);
    }
  }

  String exceptionToString(Object exception) {
    return exception.toString().replaceAll("Exception:", "");
  }
}

class BasePageController<T> extends BaseController {
  final ScrollController scrollController = ScrollController();
  int currentPage = 1;
  int pageSize = 24;
  final canLoadMore = false.obs;
  final list = <T>[].obs;

  Future refreshData() async {
    currentPage = 1;
    list.value = [];
    await loadData();
  }

  Future loadData() async {
    try {
      if (loadding) return;
      loadding = true;
      pageError.value = false;
      pageEmpty.value = false;
      pageLoadding.value = currentPage == 1;

      var result = await getData(currentPage, pageSize);
      if (result.isNotEmpty) {
        currentPage++;
        canLoadMore.value = true;
        pageEmpty.value = false;
      } else {
        canLoadMore.value = false;
        if (currentPage == 1) {
          pageEmpty.value = true;
        }
      }
      if (currentPage == 1) {
        list.value = result;
      } else {
        list.addAll(result);
      }
    } catch (e) {
      handleError(e, showPageError: currentPage == 1);
    } finally {
      loadding = false;
      pageLoadding.value = false;
    }
  }

  Future<List<T>> getData(int page, int pageSize) async {
    return [];
  }
}
