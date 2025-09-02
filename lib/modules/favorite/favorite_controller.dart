import 'dart:async';
import 'package:get/get.dart';
import 'package:pure_live/common/index.dart';

class FavoriteController extends GetxController with GetTickerProviderStateMixin {
  final SettingsService settings = Get.find<SettingsService>();
  late TabController tabController;
  late TabController tabSiteController;
  final tabBottomIndex = 0.obs;
  final tabSiteIndex = 0.obs;
  final tabOnlineIndex = 0.obs;
  bool isFirstLoad = true;
  FavoriteController() {
    tabController = TabController(length: 2, vsync: this);
    tabSiteController = TabController(length: Sites().availableSites().length + 1, vsync: this);
  }

  @override
  void onInit() {
    super.onInit();
    // 初始化关注页
    syncRooms();
    // 监听settings rooms变化
    debounce(settings.favoriteRooms, (rooms) => syncRooms(), time: const Duration(milliseconds: 1000));
    // settings.favoriteRooms.listen((rooms) => syncRooms());
    onRefresh();
    tabController.addListener(() {
      tabOnlineIndex.value = tabController.index;
    });
    tabSiteController.addListener(() {
      tabSiteIndex.value = tabSiteController.index;
    });
    // 定时自动刷新
    if (settings.autoRefreshTime.value != 0) {
      Timer.periodic(Duration(minutes: settings.autoRefreshTime.value), (timer) => onRefresh());
    }
  }

  final onlineRooms = [].obs;
  final offlineRooms = [].obs;

  void syncRooms() {
    onlineRooms.clear();
    offlineRooms.clear();
    onlineRooms.addAll(settings.favoriteRooms.where((room) => room.liveStatus == LiveStatus.live));
    offlineRooms.addAll(settings.favoriteRooms.where((room) => room.liveStatus != LiveStatus.live));
    for (var room in onlineRooms) {
      if (int.tryParse(room.watching!) == null) {
        room.watching = "0";
      }
    }
    onlineRooms.sort((a, b) => int.parse(b.watching!).compareTo(int.parse(a.watching!)));
  }

  Future<bool> onRefresh() async {
    // 如果是首次加载，则等待一秒
    if (isFirstLoad) await Future.delayed(Duration(seconds: 1));

    if (settings.favoriteRooms.value.isEmpty) return false;

    var futures = settings.favoriteRooms.value
        .where((room) => room.platform!.isNotEmpty)
        .map((room) => Sites.of(room.platform!).liveSite.getRoomDetail(roomId: room.roomId!, platform: room.platform!))
        .toList();
    try {
      for (int i = 0; i < futures.length; i += 5) {
        try {
          List<LiveRoom> rooms = await Future.wait(futures.sublist(i, i + 5 > futures.length ? futures.length : i + 5));
          for (var room in rooms) {
            try {
              settings.updateRoom(room);
            } catch (e) {
              debugPrint('Error during refresh for a single request: $e');
            }
          }
        } catch (e) {
          debugPrint('Error during refresh for a batch of requests: $e');
        }
      }
      syncRooms();
    } catch (e) {
      debugPrint('Error during refresh: $e');
    }
    isFirstLoad = false;
    return false;
  }
}
