import 'package:get/get.dart';
import 'package:simple_recorder/services/unpack_manager.dart';

// 兼容层 - 保留原有导入路径，逻辑已迁移至 UnpackManager (常驻后台, 切页不中断)
// 旧页面仍 Get.put(TsUnpackController()) 可正常工作, 但实际状态全代理到 UnpackManager

// 类型别名, 保持旧页面 import 不报错
typedef FileItem = UnpackFileItem;
typedef FileGroup = UnpackGroup;

class TsUnpackController extends GetxController {
  UnpackManager get _m => UnpackManager.instance;

  // ── 代理 Rx 状态 ──
  RxList<UnpackGroup> get groups => _m.groups;
  RxBool get isProcessing => _m.isProcessing;
  RxDouble get progress => _m.progress;
  RxInt get currentFileIndex => _m.currentFileIndex;
  RxInt get totalFiles => _m.totalFiles;
  RxString get currentFileName => _m.currentFileName;
  RxBool get hasSavePath => _m.hasSavePath;
  RxInt get sortMode => _m.sortMode;

  int get selectedCount => _m.selectedCount;
  int get unpackedSelectedCount => _m.unpackedSelectedCount;
  bool get canMergeSelected => _m.canMergeSelected;
  String? get selectedOwnerName => _m.selectedOwnerName;
  int get fragmentCount => _m.fragmentCount;

  int getMergeOrderIndex(UnpackFileItem file) => _m.getMergeOrderIndex(file);
  int getGroupFragmentCount(int i) => _m.getGroupFragmentCount(i);

  @override
  void onInit() {
    super.onInit();
    // 每次进页刷新一次 (Manager 常驻, 需手动刷新)
    _m.scanDirectory();
  }

  void scanDirectory() => _m.scanDirectory();
  void setSortMode(int m) => _m.setSortMode(m);
  void selectAll() => _m.selectAll();
  void selectUnpacked() => _m.selectUnpacked();
  void selectInterrupted() => _m.selectInterrupted();
  void deselectAll() => _m.deselectAll();
  void toggleGroup(int i) => _m.toggleGroup(i);
  void toggleCollapseAll() => _m.toggleCollapseAll();
  void toggleGroupSelection(int i) => _m.toggleGroupSelection(i);
  Future<void> deleteSelected() => _m.deleteSelected();
  Future<void> startBatchUnpack() => _m.startBatchUnpack();
  void cancelBatch() => _m.cancelBatch();
  Future<void> mergeGroupFragments(int i) => _m.mergeGroupFragments(i);
  Future<void> mergeAllFragments() => _m.mergeAllFragments();
  Future<void> mergeSelected() => _m.mergeSelected();
}
