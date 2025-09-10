import 'dart:io';
import 'dart:async';
import 'dart:developer';
import 'package:get/get.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/core/site/huya_site.dart';
import 'widgets/video_player/video_controller.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:pure_live/model/live_play_quality.dart';
import 'package:pure_live/core/danmaku/huya_danmaku.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:pure_live/modules/live_play/load_type.dart';
import 'package:pure_live/core/danmaku/douyin_danmaku.dart';
import 'package:pure_live/core/interface/live_danmaku.dart';

class LivePlayController extends StateController {
  LivePlayController({required this.room, required this.site});
  final String site;

  late final Site currentSite = Sites.of(site);

  late final LiveDanmaku liveDanmaku = Sites.of(site).liveSite.getDanmaku();

  final settings = Get.find<SettingsService>();

  final messages = <LiveMessage>[].obs;

  // 控制唯一子组件
  VideoController? videoController;

  final playerKey = GlobalKey();

  final danmakuViewKey = GlobalKey();

  final LiveRoom room;

  Rx<LiveRoom?> detail = Rx<LiveRoom?>(LiveRoom());

  final success = false.obs;

  var liveStatus = false.obs;

  Map<String, List<String>> liveStream = {};

  /// 清晰度数据
  RxList<LivePlayQuality> qualites = RxList<LivePlayQuality>();

  /// 当前清晰度
  final currentQuality = 0.obs;

  /// 线路数据
  RxList<String> playUrls = RxList<String>();

  /// 当前线路
  final currentLineIndex = 0.obs;

  int loopCount = 0;

  int lastExitTime = 0;

  /// 双击退出Flag
  bool doubleClickExit = false;

  /// 双击退出Timer
  Timer? doubleClickTimer;

  var isFirstLoad = true.obs;
  // 0 代表向上 1 代表向下
  int isNextOrPrev = 0;

  // 当前直播间信息 下一个频道或者上一个
  var currentPlayRoom = LiveRoom().obs;

  var getVideoSuccess = true.obs;

  var lastChannelIndex = 0.obs;

  Timer? channelTimer;

  Timer? loadRefreshRoomTimer;

  Timer? networkTimer;
  // 切换线路会添加到这个数组里面
  var isLastLine = false.obs;

  var hasError = false.obs;

  var loadTimeOut = true.obs;
  // 是否是手动切换线路
  var isActive = false.obs;

  var isFullScreen = false.obs;

  Future<bool> onBackPressed({bool directiveExit = false}) async {
    if (videoController!.showSettting.value) {
      videoController?.showSettting.toggle();
      return await Future.value(false);
    }
    if (videoController!.isFullscreen.value) {
      videoController?.exitFullScreen();
      return await Future.value(false);
    }
    bool doubleExit = Get.find<SettingsService>().doubleExit.value;
    if (!doubleExit || directiveExit) {
      disPoserPlayer();
      return Future.value(true);
    }
    int nowExitTime = DateTime.now().millisecondsSinceEpoch;
    if (nowExitTime - lastExitTime > 1000) {
      lastExitTime = nowExitTime;
      SmartDialog.showToast(S.current.double_click_to_exit);
      return await Future.value(false);
    }
    disPoserPlayer();
    return await Future.value(true);
  }

  @override
  void onInit() {
    super.onInit();
    // 发现房间ID 会变化 使用静态列表ID 对比
    log('onInit', name: 'LivePlayController');
    currentPlayRoom.value = room;
    onInitPlayerState(firstLoad: true);
    isFirstLoad.listen((p0) {
      if (isFirstLoad.value) {
        Timer(const Duration(seconds: 8), () {
          isFirstLoad.value = false;
          if (getVideoSuccess.value == false) {
            loadTimeOut.value = true;
            SmartDialog.showToast("获取直播间信息失败,请重新获取", displayTime: const Duration(seconds: 2));
          }
        });
      }
    });

    isLastLine.listen((p0) {
      if (isLastLine.value && hasError.value && isActive.value == false) {
        // 刷新到了最后一路线 并且有错误
        if (Get.currentRoute == '/live_play') {
          SmartDialog.showToast("当前房间无法播放,正在为您刷新直播间信息...", displayTime: const Duration(seconds: 2));
          isLastLine.value = false;
          isFirstLoad.value = true;
          restoryQualityAndLines();
          resetRoom(Sites.of(currentPlayRoom.value.platform!), currentPlayRoom.value.roomId!);
        }
      } else {
        if (success.value) {
          isActive.value = false;
          loadRefreshRoomTimer?.cancel();
        }
      }
    });
  }

  void resetRoom(Site site, String roomId) async {
    success.value = false;
    hasError.value = false;
    if (videoController != null && !videoController!.hasDestory) {
      await videoController?.destory();
      videoController = null;
    }

    isFirstLoad.value = true;
    getVideoSuccess.value = true;
    loadTimeOut.value = false;
    Timer(const Duration(milliseconds: 4000), () {
      if (Get.currentRoute == '/live_play') {
        log('resetRoom', name: 'LivePlayController');
        onInitPlayerState(firstLoad: true);
      }
    });
  }

  Future<LiveRoom> onInitPlayerState({
    ReloadDataType reloadDataType = ReloadDataType.refreash,
    int line = 0,
    bool active = false,
    bool firstLoad = false,
  }) async {
    isActive.value = active;
    isFirstLoad.value = firstLoad;
    var liveRoom = await currentSite.liveSite.getRoomDetail(
      roomId: currentPlayRoom.value.roomId!,
      platform: currentPlayRoom.value.platform!,
    );
    if (currentSite.id == Sites.iptvSite) {
      liveRoom = liveRoom.copyWith(title: currentPlayRoom.value.title!, nick: currentPlayRoom.value.nick!);
    }
    isLastLine.value = calcIsLastLine(line) && reloadDataType == ReloadDataType.changeLine;
    if (isLastLine.value) {
      hasError.value = true;
    } else {
      hasError.value = false;
    }
    // active 代表用户是否手动切换路线 只有不是手动自动切换才会显示路线错误信息
    if (isLastLine.value && hasError.value && active == false) {
      restoryQualityAndLines();
      getVideoSuccess.value = false;
      isFirstLoad.value = false;
      success.value = false;
      return liveRoom;
    } else {
      handleCurrentLineAndQuality(reloadDataType: reloadDataType, line: line, active: active);
      detail.value = liveRoom;
      if (liveRoom.liveStatus == LiveStatus.unknown) {
        if (Get.currentRoute == '/live_play') {
          SmartDialog.showToast("获取直播间信息失败,请重新获取", displayTime: const Duration(seconds: 2));
          getVideoSuccess.value = false;
          isFirstLoad.value = false;
        }
        return liveRoom;
      }

      // 开始播放
      liveStatus.value = liveRoom.status! || liveRoom.isRecord!;
      if (liveStatus.value) {
        await getPlayQualites();
        getVideoSuccess.value = true;
        if (currentPlayRoom.value.platform == Sites.iptvSite) {
          settings.addRoomToHistory(currentPlayRoom.value);
        } else {
          settings.addRoomToHistory(liveRoom);
        }
        // start danmaku server
        List<String> except = ['kuaishou', 'iptv', 'cc'];
        if (except.indexWhere((element) => element == liveRoom.platform!) == -1) {
          liveDanmaku.stop();
          initDanmau();
          liveDanmaku.start(liveRoom.danmakuData);
        }
      } else {
        isFirstLoad.value = false;
        success.value = false;
        getVideoSuccess.value = true;
        if (liveRoom.liveStatus == LiveStatus.banned) {
          SmartDialog.showToast("服务器错误,请稍后获取", displayTime: const Duration(seconds: 2));
        } else {
          SmartDialog.showToast("当前主播未开播或主播已下播", displayTime: const Duration(seconds: 2));
        }
        restoryQualityAndLines();
      }

      return liveRoom;
    }
  }

  bool calcIsLastLine(int line) {
    var lastLine = line + 1;
    if (playUrls.isEmpty) {
      return true;
    }
    if (playUrls.length == 1) {
      return true;
    }
    if (lastLine == playUrls.length - 1) {
      return true;
    }
    return false;
  }

  void disPoserPlayer() {
    videoController?.destory();
    videoController = null;
    liveDanmaku.stop();
    success.value = false;
  }

  void handleCurrentLineAndQuality({
    ReloadDataType reloadDataType = ReloadDataType.refreash,
    int line = 0,
    bool active = false,
  }) {
    if (reloadDataType == ReloadDataType.changeLine && active == false) {
      if (line == playUrls.length - 1) {
        currentLineIndex.value = 0;
      } else {
        currentLineIndex.value = currentLineIndex.value + 1;
      }
      loopCount++;
      isFirstLoad.value = false;
    }
  }

  void restoryQualityAndLines() {
    playUrls.value = [];
    currentLineIndex.value = 0;
    qualites.value = [];
    loopCount = 0;
    currentQuality.value = 0;
  }

  /// 初始化弹幕接收事件
  void initDanmau() {
    if (detail.value!.isRecord!) {
      messages.add(
        LiveMessage(
          type: LiveMessageType.chat,
          userName: "系统消息",
          message: "当前主播未开播，正在轮播录像",
          color: LiveMessageColor.white,
        ),
      );
    }
    messages.add(
      LiveMessage(type: LiveMessageType.chat, userName: "系统消息", message: "开始连接弹幕服务器", color: LiveMessageColor.white),
    );
    liveDanmaku.onMessage = (msg) {
      if (msg.type == LiveMessageType.chat) {
        if (settings.shieldList.every((element) => !msg.message.contains(element))) {
          messages.add(msg);
          if (videoController != null && videoController!.hasDestory == false) {
            videoController?.sendDanmaku(msg);
          }
        }
      }
    };
    liveDanmaku.onClose = (msg) {
      messages.add(
        LiveMessage(type: LiveMessageType.chat, userName: "系统消息", message: msg, color: LiveMessageColor.white),
      );
    };
    liveDanmaku.onReady = () {
      messages.add(
        LiveMessage(type: LiveMessageType.chat, userName: "系统消息", message: "弹幕服务器连接正常", color: LiveMessageColor.white),
      );
    };
  }

  void setResolution(String quality, String index) {
    if (videoController != null && videoController!.hasDestory == false) {
      videoController!.destory();
    }
    currentQuality.value = qualites.map((e) => e.quality).toList().indexWhere((e) => e == quality);
    currentLineIndex.value = int.tryParse(index) ?? 0;
    onInitPlayerState(
      reloadDataType: ReloadDataType.changeLine,
      line: currentLineIndex.value,
      active: true,
      firstLoad: false,
    );
  }

  /// 初始化播放器
  Future<void> getPlayQualites() async {
    try {
      var playQualites = await currentSite.liveSite.getPlayQualites(detail: detail.value!);
      if (playQualites.isEmpty) {
        SmartDialog.showToast("无法读取视频信息,请重新获取", displayTime: const Duration(seconds: 2));
        getVideoSuccess.value = false;
        isFirstLoad.value = false;
        success.value = false;
        return;
      }
      qualites.value = playQualites;
      // 第一次加载 使用系统默认线路
      if (isFirstLoad.value) {
        int qualityLevel = settings.resolutionsList.indexOf(settings.preferResolution.value);
        if (qualityLevel == 0) {
          //最高
          currentQuality.value = 0;
        } else if (qualityLevel == settings.resolutionsList.length - 1) {
          //最低
          currentQuality.value = playQualites.length - 1;
        } else {
          //中间值
          int middle = (playQualites.length / 2).floor();
          currentQuality.value = middle;
        }
      }
      isFirstLoad.value = false;
      getPlayUrl();
    } catch (e) {
      SmartDialog.showToast("无法读取视频信息,请重新获取");
      getVideoSuccess.value = false;
      isFirstLoad.value = false;
      success.value = false;
    }
  }

  Future<void> getPlayUrl() async {
    var playUrl = await currentSite.liveSite.getPlayUrls(
      detail: detail.value!,
      quality: qualites[currentQuality.value],
    );
    if (playUrl.isEmpty) {
      SmartDialog.showToast("无法读取播放地址,请重新获取", displayTime: const Duration(seconds: 2));
      getVideoSuccess.value = false;
      isFirstLoad.value = false;
      success.value = false;
      return;
    }
    playUrls.value = playUrl;
    setPlayer();
  }

  void setPlayer() async {
    Map<String, String> headers = {};
    if (currentSite.id == Sites.bilibiliSite) {
      headers = {
        "cookie": settings.bilibiliCookie.value,
        "authority": "api.bilibili.com",
        "accept":
            "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7",
        "accept-language": "zh-CN,zh;q=0.9",
        "cache-control": "no-cache",
        "dnt": "1",
        "pragma": "no-cache",
        "sec-ch-ua": '"Not A(Brand";v="99", "Google Chrome";v="121", "Chromium";v="121"',
        "sec-ch-ua-mobile": "?0",
        "sec-ch-ua-platform": '"macOS"',
        "sec-fetch-dest": "document",
        "sec-fetch-mode": "navigate",
        "sec-fetch-site": "none",
        "sec-fetch-user": "?1",
        "upgrade-insecure-requests": "1",
        "user-agent":
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36",
        "referer": "https://live.bilibili.com",
      };
    } else if (currentSite.id == Sites.huyaSite) {
      var ua = await HuyaSite().getHuYaUA();
      headers = {"user-agent": ua, "origin": "https://www.huya.com"};
    }

    videoController = VideoController(
      playerKey: playerKey,
      room: detail.value!,
      datasourceType: 'network',
      videoPlayerIndex: currentSite.id == Sites.huyaSite && settings.videoPlayerIndex.value == 1
          ? 0
          : settings.videoPlayerIndex.value,
      datasource: playUrls.value[currentLineIndex.value],
      allowScreenKeepOn: settings.enableScreenKeepOn.value,
      allowBackgroundPlay: settings.enableBackgroundPlay.value,
      fullScreenByDefault: settings.enableFullScreenDefault.value,
      autoPlay: true,
      headers: headers,
      qualiteName: qualites[currentQuality.value].quality,
      currentLineIndex: currentLineIndex.value,
      currentQuality: currentQuality.value,
    );
    success.value = true;

    networkTimer?.cancel();
    networkTimer = Timer(const Duration(seconds: 10), () async {
      if (videoController != null && videoController!.hasDestory == false) {
        final connectivityResults = await Connectivity().checkConnectivity();
        if (!connectivityResults.contains(ConnectivityResult.none)) {
          if (!videoController!.isActivePause.value && videoController!.isPlaying.value == false) {
            videoController!.refresh();
          }
        }
      }
    });

    videoController?.isFullscreen.listen((value) {
      isFullScreen.value = value;
    });
  }

  Future<void> openNaviteAPP() async {
    var naviteUrl = "";
    var webUrl = "";
    if (site == Sites.bilibiliSite) {
      naviteUrl = "bilibili://live/${detail.value?.roomId}";
      webUrl = "https://live.bilibili.com/${detail.value?.roomId}";
    } else if (site == Sites.douyinSite) {
      var args = detail.value?.danmakuData as DouyinDanmakuArgs;
      naviteUrl = "snssdk1128://webcast_room?room_id=${args.roomId}";
      webUrl = "https://live.douyin.com/${args.webRid}";
    } else if (site == Sites.huyaSite) {
      var args = detail.value?.danmakuData as HuyaDanmakuArgs;
      naviteUrl =
          "yykiwi://homepage/index.html?banneraction=https%3A%2F%2Fdiy-front.cdn.huya.com%2Fzt%2Ffrontpage%2Fcc%2Fupdate.html%3Fhyaction%3Dlive%26channelid%3D${args.subSid}%26subid%3D${args.subSid}%26liveuid%3D${args.subSid}%26screentype%3D1%26sourcetype%3D0%26fromapp%3Dhuya_wap%252Fclick%252Fopen_app_guide%26&fromapp=huya_wap/click/open_app_guide";
      webUrl = "https://www.huya.com/${detail.value?.roomId}";
    } else if (site == Sites.douyuSite) {
      naviteUrl =
          "douyulink://?type=90001&schemeUrl=douyuapp%3A%2F%2Froom%3FliveType%3D0%26rid%3D${detail.value?.roomId}";
      webUrl = "https://www.douyu.com/${detail.value?.roomId}";
    } else if (site == Sites.ccSite) {
      log(detail.value!.userId.toString(), name: "cc_user_id");
      naviteUrl = "cc://join-room/${detail.value?.roomId}/${detail.value?.userId}/";
      webUrl = "https://cc.163.com/${detail.value?.roomId}";
    } else if (site == Sites.kuaishouSite) {
      naviteUrl =
          "kwai://liveaggregatesquare?liveStreamId=${detail.value?.link}&recoStreamId=${detail.value?.link}&recoLiveStreamId=${detail.value?.link}&liveSquareSource=28&path=/rest/n/live/feed/sharePage/slide/more&mt_product=H5_OUTSIDE_CLIENT_SHARE";
      webUrl = "https://live.kuaishou.com/u/${detail.value?.roomId}";
    }
    try {
      if (Platform.isAndroid) {
        await launchUrlString(naviteUrl, mode: LaunchMode.externalApplication);
      } else {
        await launchUrlString(webUrl, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      SmartDialog.showToast("无法打开APP，将使用浏览器打开");
      await launchUrlString(webUrl, mode: LaunchMode.externalApplication);
    }
  }

  @override
  void onClose() {
    super.onClose();
    disPoserPlayer();
  }

  @override
  void dispose() {
    disPoserPlayer();
    super.dispose();
  }
}
