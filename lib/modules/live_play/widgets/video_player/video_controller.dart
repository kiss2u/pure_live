import 'dart:io';
import 'dart:async';
import 'dart:developer';
import 'dart:math' as math;
import 'package:get/get.dart';
import 'video_controller_panel.dart';
import 'package:flutter/services.dart';
import 'package:floating/floating.dart';
import 'package:pure_live/common/index.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:canvas_danmaku/danmaku_controller.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:canvas_danmaku/models/danmaku_option.dart';
import 'package:pure_live/modules/live_play/load_type.dart';
import 'package:canvas_danmaku/models/danmaku_content_item.dart';
import 'package:pure_live/modules/live_play/live_play_controller.dart';
import 'package:media_kit_video/media_kit_video.dart' as media_kit_video;
import 'package:flutter_volume_controller/flutter_volume_controller.dart';

class VideoController with ChangeNotifier {
  final GlobalKey playerKey;

  final GlobalKey containerKey = GlobalKey();
  final LiveRoom room;
  final String datasourceType;
  String datasource;
  final bool allowBackgroundPlay;
  final bool allowScreenKeepOn;
  final bool allowFullScreen;
  final bool fullScreenByDefault;
  final bool autoPlay;
  final Map<String, String> headers;

  final int videoPlayerIndex;
  final isVertical = false.obs;
  final videoFitIndex = 0.obs;
  final videoFit = BoxFit.contain.obs;
  final mediaPlayerControllerInitialized = false.obs;

  ScreenBrightness brightnessController = ScreenBrightness();

  double initBrightness = 0.0;

  final String qualiteName;

  final int currentLineIndex;

  final int currentQuality;

  final hasError = false.obs;

  final isPlaying = false.obs;

  final isBuffering = false.obs;

  final isPipMode = false.obs;

  final isFullscreen = false.obs;

  final isWindowFullscreen = false.obs;

  bool hasDestory = false;

  bool get supportPip => Platform.isAndroid;

  bool get supportWindowFull => Platform.isWindows || Platform.isLinux;

  bool get fullscreenUI => isFullscreen.value || isWindowFullscreen.value;

  final refreshCompleted = true.obs;

  final videoSizeWidth = 0.0.obs;

  final videoSizeHeight = 0.0.obs;

  // ignore: prefer_typing_uninitialized_variables
  late final Floating pip;
  // Video player status
  // A [GlobalKey<VideoState>] is required to access the programmatic fullscreen interface.
  late final GlobalKey<media_kit_video.VideoState> key = GlobalKey<media_kit_video.VideoState>();

  // Create a [Player] to control playback.
  late Player player;
  // CeoController] to handle video output from [Player].
  late media_kit_video.VideoController mediaPlayerController;
  BetterPlayerController? mobileController;
  final playerRefresh = false.obs;

  GlobalKey<BrightnessVolumnDargAreaState> brightnessKey = GlobalKey<BrightnessVolumnDargAreaState>();

  LivePlayController livePlayController = Get.find<LivePlayController>();

  final SettingsService settings = Get.find<SettingsService>();

  bool enableCodec = true;

  bool playerCompatMode = false;

  // 是否手动暂停
  var isActivePause = true.obs;

  Timer? hasActivePause;

  // Controller ui status
  ///State of navigator on widget created
  late NavigatorState navigatorState;

  ///Flag which determines if widget has initialized

  Timer? showControllerTimer;
  final showController = true.obs;
  final showSettting = false.obs;
  final showLocked = false.obs;
  final danmuKey = GlobalKey();

  List<DanmakuController> danmakuControllers = [];
  Timer? _debounceTimer;

  void enableController() {
    showControllerTimer?.cancel();
    showControllerTimer = Timer(const Duration(seconds: 2), () {
      showController.value = false;
    });
    showController.value = true;
  }

  final hideDanmaku = false.obs;
  final danmakuArea = 1.0.obs;
  final danmakuSpeed = 8.0.obs;
  final danmakuFontSize = 16.0.obs;
  final danmakuFontBorder = 4.0.obs;
  final danmakuOpacity = 1.0.obs;
  VideoController({
    required this.playerKey,
    required this.room,
    required this.datasourceType,
    required this.datasource,
    required this.headers,
    this.allowBackgroundPlay = false,
    this.allowScreenKeepOn = false,
    this.allowFullScreen = true,
    this.fullScreenByDefault = false,
    this.autoPlay = true,
    BoxFit fitMode = BoxFit.contain,
    required this.qualiteName,
    required this.currentLineIndex,
    required this.currentQuality,
    required this.videoPlayerIndex,
  }) {
    videoFitIndex.value = settings.videoFitIndex.value;
    videoFit.value = settings.videofitArrary[videoFitIndex.value];
    hideDanmaku.value = settings.hideDanmaku.value;
    danmakuArea.value = settings.danmakuArea.value;
    danmakuSpeed.value = settings.danmakuSpeed.value;
    danmakuFontSize.value = settings.danmakuFontSize.value;
    danmakuFontBorder.value = settings.danmakuFontBorder.value;
    danmakuOpacity.value = settings.danmakuOpacity.value;
    initPagesConfig();
  }

  void initPagesConfig() {
    if (allowScreenKeepOn) WakelockPlus.enable();
    initVideoController();
    initDanmaku();
    initBattery();
  }

  // Battery level control
  final Battery _battery = Battery();
  final batteryLevel = 100.obs;

  final angle = 0.0.obs;
  void initBattery() {
    if (Platform.isAndroid || Platform.isIOS) {
      _battery.batteryLevel.then((value) => batteryLevel.value = value);
      _battery.onBatteryStateChanged.listen((BatteryState state) async {
        batteryLevel.value = await _battery.batteryLevel;
      });
    }
  }

  void initVideoController() async {
    FlutterVolumeController.updateShowSystemUI(false);
    registerVolumeListener();
    if (videoPlayerIndex == 0 || Platform.isWindows) {
      enableCodec = settings.enableCodec.value;
      playerCompatMode = settings.playerCompatMode.value;
      player = Player();
      if (player.platform is NativePlayer) {
        (player.platform as dynamic).setProperty('cache', 'no'); // --cache=<yes|no|auto>
        (player.platform as dynamic).setProperty('cache-secs', '0'); // --cache-secs=<seconds> with cache but why not.
        (player.platform as dynamic).setProperty('demuxer-seekable-cache', 'no');
        (player.platform as dynamic).setProperty('demuxer-max-back-bytes', '0'); // --demuxer-max-back-bytes=<bytesize>
        (player.platform as dynamic).setProperty('demuxer-donate-buffer', 'no'); // --demuxer-donate-buffer==<yes|no>
      }
      mediaPlayerController = media_kit_video.VideoController(
        player,
        configuration: playerCompatMode
            ? VideoControllerConfiguration(vo: 'mediacodec_embed', hwdec: 'mediacodec')
            : VideoControllerConfiguration(
                enableHardwareAcceleration: enableCodec,
                androidAttachSurfaceAfterVideoParameters: false,
              ),
      );
      setDataSource(datasource);
      mediaPlayerController.player.stream.playing.listen((bool playing) {
        isPlaying.value = playing;
        if (playing && mediaPlayerControllerInitialized.value == false) {
          mediaPlayerControllerInitialized.value = true;
          setVolume(settings.volume.value);
        }
      });
      mediaPlayerController.player.stream.error.listen((event) {
        log('video error: $event', name: 'video_player');
        if (event.toString().contains('Failed to open')) {
          hasError.value = true;
          isPlaying.value = false;
        }
      });
      debounce(hasError, (callback) {
        if (hasError.value && !livePlayController.isLastLine.value) {
          SmartDialog.showToast("视频播放失败,正在为您切换线路");
          changeLine();
        }
      }, time: const Duration(seconds: 2));

      showController.listen((p0) {
        if (showController.value) {
          if (isPlaying.value) {
            isActivePause.value = false;
          }
        }
        if (isPlaying.value) {
          hasActivePause?.cancel();
        }
      });

      isPlaying.listen((p0) {
        // 代表手动暂停了
        if (!isPlaying.value) {
          if (showController.value) {
            isActivePause.value = true;
            hasActivePause?.cancel();
          } else {
            if (isActivePause.value) {
              hasActivePause = Timer(const Duration(seconds: 20), () {
                // 暂停了
                SmartDialog.showToast("系统监测视频已停止播放,正在为您刷新视频");
                isActivePause.value = false;
                refresh();
              });
            }
          }
        } else {
          hasActivePause?.cancel();
          isActivePause.value = false;
        }
      });

      mediaPlayerControllerInitialized.listen((value) {
        if (fullScreenByDefault && datasource.isNotEmpty && value) {
          Timer(const Duration(milliseconds: 500), () => toggleFullScreen());
        }
      });
      if (Platform.isAndroid) {
        pip = Floating();
        pip.pipStatusStream.listen((status) {
          if (status == PiPStatus.enabled) {
            isPipMode.value = true;
            key.currentState?.enterFullscreen();
          } else {
            isPipMode.value = false;
            key.currentState?.exitFullscreen();
          }
        });
      }
    } else {
      mobileController = BetterPlayerController(
        BetterPlayerConfiguration(
          controlsConfiguration: BetterPlayerControlsConfiguration(
            playerTheme: BetterPlayerTheme.custom,
            customControlsBuilder: (controller, onControlsVisibilityChanged) => VideoControllerPanel(controller: this),
          ),
          autoPlay: true,
          fit: videoFit.value,
          allowedScreenSleep: !allowScreenKeepOn,
          autoDetectFullscreenDeviceOrientation: true,
          autoDetectFullscreenAspectRatio: true,
          errorBuilder: (context, errorMessage) => Container(),
          handleLifecycle: true,
        ),
      );
      mobileController?.setControlsEnabled(false);
      setDataSource(datasource);

      mobileController?.addEventsListener(mobileStateListener);
      mediaPlayerControllerInitialized.listen((value) {
        if (fullScreenByDefault && datasource.isNotEmpty && value) {
          Timer(const Duration(milliseconds: 500), () => toggleFullScreen());
        }
      });
      debounce(hasError, (callback) {
        if (hasError.value && !livePlayController.isLastLine.value) {
          SmartDialog.showToast("视频播放失败,正在为您切换线路");
          changeLine();
        }
      }, time: const Duration(seconds: 2));

      showController.listen((p0) {
        if (showController.value) {
          if (isPlaying.value) {
            isActivePause.value = false;
          }
        }
        if (isPlaying.value) {
          hasActivePause?.cancel();
        }
      });

      isPlaying.listen((p0) {
        // 代表手动暂停了
        if (!isPlaying.value) {
          if (showController.value) {
            isActivePause.value = true;
            hasActivePause?.cancel();
          } else {
            if (isActivePause.value) {
              hasActivePause = Timer(const Duration(seconds: 20), () {
                // 暂停了
                SmartDialog.showToast("系统监测视频已停止播放,正在为您刷新视频");
                isActivePause.value = false;
                refresh();
              });
            }
          }
        } else {
          hasActivePause?.cancel();
          isActivePause.value = false;
        }
      });
    }
  }

  dynamic mobileStateListener(BetterPlayerEvent event) {
    if (mobileController?.videoPlayerController != null) {
      hasError.value = mobileController?.videoPlayerController?.value.hasError ?? false;
      log('betterPlayerEventType: ${event.betterPlayerEventType} ${event.parameters}', name: 'video_player');

      if (event.betterPlayerEventType == BetterPlayerEventType.exception) {
        log('betterPlayerEventType: ${event.parameters}', name: 'video_player');
      }

      log('isVideoInitialized: ${mobileController!.isVideoInitialized()}', name: 'video_player');
      isPlaying.value = mobileController?.isPlaying() ?? false;
      isBuffering.value = mobileController?.isBuffering() ?? false;
      isPipMode.value = mobileController?.videoPlayerController?.value.isPip ?? false;
      if (isPlaying.value && mediaPlayerControllerInitialized.value == false) {
        mediaPlayerControllerInitialized.value = true;
        setVolume(settings.volume.value);
      }
      log(mobileController!.isBuffering().toString(), name: 'video_player');
    }
  }

  void debounceListen(Function? func, [int delay = 1000]) {
    if (_debounceTimer != null) {
      _debounceTimer?.cancel();
    }
    _debounceTimer = Timer(Duration(milliseconds: delay), () {
      func?.call();
      _debounceTimer = null;
    });
  }

  void refreshView() {
    refreshCompleted.value = false;
    Timer(const Duration(microseconds: 200), () {
      brightnessKey = GlobalKey<BrightnessVolumnDargAreaState>();
      refreshCompleted.value = true;
    });
  }

  void initDanmaku() {
    hideDanmaku.value = PrefUtil.getBool('hideDanmaku') ?? false;
    hideDanmaku.listen((data) {
      if (data) {
        for (var controller in danmakuControllers) {
          controller.clear();
        }
      }
      PrefUtil.setBool('hideDanmaku', data);
      settings.hideDanmaku.value = data;
    });
    danmakuArea.value = PrefUtil.getDouble('danmakuArea') ?? 1.0;
    danmakuArea.listen((data) {
      PrefUtil.setDouble('danmakuArea', data);
      settings.danmakuArea.value = data;
      updateDanmaku();
    });
    danmakuSpeed.value = PrefUtil.getDouble('danmakuSpeed') ?? 8;
    danmakuSpeed.listen((data) {
      PrefUtil.setDouble('danmakuSpeed', data);
      settings.danmakuSpeed.value = data;
      updateDanmaku();
    });
    danmakuFontSize.value = PrefUtil.getDouble('danmakuFontSize') ?? 16;
    danmakuFontSize.listen((data) {
      PrefUtil.setDouble('danmakuFontSize', data);
      settings.danmakuFontSize.value = data;
      updateDanmaku();
    });
    danmakuFontBorder.value = PrefUtil.getDouble('danmakuFontBorder') ?? 4.0;
    danmakuFontBorder.listen((data) {
      PrefUtil.setDouble('danmakuFontBorder', data);
      settings.danmakuFontBorder.value = data;
      updateDanmaku();
    });
    danmakuOpacity.value = PrefUtil.getDouble('danmakuOpacity') ?? 1.0;
    danmakuOpacity.listen((data) {
      PrefUtil.setDouble('danmakuOpacity', data);
      settings.danmakuOpacity.value = data;
      updateDanmaku();
    });
  }

  void updateDanmaku() {
    for (var controller in danmakuControllers) {
      controller.updateOption(
        DanmakuOption(
          fontSize: danmakuFontSize.value,
          area: danmakuArea.value,
          duration: danmakuSpeed.value.toInt(),
          opacity: danmakuOpacity.value,
          fontWeight: danmakuFontBorder.value.toInt(),
        ),
      );
    }
  }

  void setDanmukuController(DanmakuController controller) {
    danmakuControllers.add(controller);
  }

  void sendDanmaku(LiveMessage msg) {
    if (hideDanmaku.value) return;
    if (isPlaying.value) {
      for (var controller in danmakuControllers) {
        controller.addDanmaku(
          DanmakuContentItem(msg.message, color: Color.fromARGB(255, msg.color.r, msg.color.g, msg.color.b)),
        );
      }
    }
  }

  @override
  void dispose() async {
    if (hasDestory == false) {
      await destory();
    }

    super.dispose();
  }

  void refresh() async {
    await destory();
    Timer(const Duration(seconds: 2), () {
      livePlayController.onInitPlayerState(reloadDataType: ReloadDataType.refreash);
    });
  }

  void changeLine({bool active = false}) async {
    // 播放错误 不一定是线路问题 先切换路线解决 后面尝试通知用户切换播放器
    await destory();
    Timer(const Duration(seconds: 2), () {
      livePlayController.onInitPlayerState(
        reloadDataType: ReloadDataType.changeLine,
        line: currentLineIndex,
        active: active,
      );
    });
  }

  Future<void> destory() async {
    isPlaying.value = false;
    hasError.value = false;
    livePlayController.success.value = false;
    hasDestory = true;
    if (allowScreenKeepOn) WakelockPlus.disable();

    FlutterVolumeController.removeListener();
    if (Platform.isAndroid || Platform.isIOS) {
      brightnessController.resetApplicationScreenBrightness();
      if (videoPlayerIndex == 0) {
        if (key.currentState?.isFullscreen() ?? false) {
          key.currentState?.exitFullscreen();
        }
        player.dispose();
      } else {
        if (mobileController?.isFullScreen ?? false) {
          mobileController?.exitFullScreen();
        }
        mobileController?.dispose();
      }
    } else {
      if (key.currentState?.isFullscreen() ?? false) {
        key.currentState?.exitFullscreen();
      }
      player.dispose();
    }
  }

  void setDataSource(String url) async {
    datasource = url;
    // fix datasource empty error
    if (datasource.isEmpty) {
      hasError.value = true;
      return;
    } else {
      hasError.value = false;
    }
    if (Platform.isWindows || videoPlayerIndex == 0) {
      player.pause();
      player.open(Media(datasource, httpHeaders: headers));
    } else {
      BetterPlayerVideoFormat? videoFormat;
      if (room.platform == Sites.bilibiliSite) {
        videoFormat = BetterPlayerVideoFormat.hls;
      }
      if (room.platform == Sites.huyaSite) {
        if (url.contains('.m3u8')) {
          videoFormat = BetterPlayerVideoFormat.hls;
        }
      }

      final result = await mobileController?.setupDataSource(
        BetterPlayerDataSource(
          BetterPlayerDataSourceType.network,
          url,
          videoFormat: videoFormat,
          liveStream: true,
          notificationConfiguration: allowBackgroundPlay
              ? BetterPlayerNotificationConfiguration(
                  showNotification: true,
                  title: room.title,
                  author: room.nick,
                  imageUrl: room.avatar,
                  activityName: "MainActivity",
                )
              : null,
          headers: headers,
          bufferingConfiguration: BetterPlayerBufferingConfiguration(
            minBufferMs: 1000, // 增加最小缓冲时间
            maxBufferMs: 1000, // 增加最大缓冲时间
            bufferForPlaybackMs: 1000, // 开始播放前的缓冲时间
            bufferForPlaybackAfterRebufferMs: 1000, // 重新缓冲后的缓冲时间
          ),
          cacheConfiguration: BetterPlayerCacheConfiguration(
            useCache: false, // 禁用缓存
          ),
        ),
      );
      log(result.toString(), name: 'video_player');
    }
    notifyListeners();
  }

  void setVideoFit(BoxFit fit) {
    videoFit.value = fit;
    if (videoPlayerIndex == 0) {
      key.currentState?.update(fit: fit);
    } else {
      mobileController?.setOverriddenFit(videoFit.value);
      mobileController?.retryDataSource();
    }
  }

  void togglePlayPause() {
    if (Platform.isWindows || videoPlayerIndex == 0) {
      mediaPlayerController.player.playOrPause();
    } else {
      isPlaying.value ? mobileController!.pause() : mobileController!.play();
    }
  }

  void exitFullScreen() {
    isFullscreen.value = false;
    if (Platform.isWindows || videoPlayerIndex == 0) {
      if (key.currentState?.isFullscreen() ?? false) {
        key.currentState?.exitFullscreen();
      }
    } else {
      mobileController?.exitFullScreen();
    }
    showSettting.value = false;
  }

  /// 设置横屏
  Future setLandscapeOrientation() async {
    isVertical.value = false;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
  }

  /// 设置竖屏
  Future setPortraitOrientation() async {
    isVertical.value = true;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
  }

  void toggleFullScreen() async {
    // disable locked
    showLocked.value = false;
    // fix obx setstate when build
    showControllerTimer?.cancel();
    Timer(const Duration(seconds: 2), () {
      enableController();
    });
    if (Platform.isWindows || videoPlayerIndex == 0) {
      if (isFullscreen.value) {
        key.currentState?.exitFullscreen();
      } else {
        key.currentState?.enterFullscreen();
      }
      isFullscreen.toggle();
      refreshView();
    } else {
      mobileController?.toggleFullScreen();
      Timer(const Duration(milliseconds: 400), () {
        isFullscreen.toggle();
        // fix immersion status bar problem
        if (Platform.isAndroid) {
          SystemChrome.setEnabledSystemUIMode(
            !isFullscreen.value ? SystemUiMode.edgeToEdge : SystemUiMode.immersiveSticky,
          );
        }
      });
    }
  }

  void toggleWindowFullScreen() {
    // disable locked
    showLocked.value = false;
    // fix obx setstate when build
    showControllerTimer?.cancel();
    Timer(const Duration(seconds: 2), () {
      enableController();
    });

    if (Platform.isWindows || Platform.isLinux) {
      if (!isWindowFullscreen.value) {
        Get.to(() => DesktopFullscreen(controller: this, key: UniqueKey()));
      } else {
        Navigator.of(Get.context!).pop();
      }
      isWindowFullscreen.toggle();
    } else {
      throw UnimplementedError('Unsupported Platform');
    }
    enableController();
    refreshView();
  }

  void enterPipMode(BuildContext context) async {
    if ((Platform.isAndroid || Platform.isIOS)) {
      for (var danmakuController in danmakuControllers) {
        danmakuController.onClear();
        danmakuController.resume();
      }
      if (Platform.isWindows || videoPlayerIndex == 0) {
        await pip.enable(ImmediatePiP());
      } else {
        if (await mobileController?.isPictureInPictureSupported() ?? false) {
          isPipMode.value = true;
          mobileController?.enablePictureInPicture(playerKey);
        }
      }
    }
  }

  // 注册音量变化监听器
  void registerVolumeListener() {
    FlutterVolumeController.addListener((volume) {
      // 音量变化时的回调
      if (Platform.isAndroid) {
        settings.volume.value = volume;
      }
    });
  }

  // volume & brightness
  Future<double?> volume() async {
    if (Platform.isWindows) {
      return mediaPlayerController.player.state.volume / 100;
    }
    return await FlutterVolumeController.getVolume();
  }

  Future<double> brightness() async {
    return await brightnessController.application;
  }

  void setVolume(double value) async {
    if (Platform.isWindows) {
      mediaPlayerController.player.setVolume(value * 100);
    } else {
      await FlutterVolumeController.setVolume(value);
    }
    settings.volume.value = value;
  }

  void setBrightness(double value) async {
    if (Platform.isAndroid || Platform.isIOS) {
      await brightnessController.setApplicationScreenBrightness(value);
    }
  }

  void rotateScreen() {
    angle.value = (angle.value + (90 * (math.pi / 180))) % (2 * math.pi);
    enableController();
  }

  // 判断是否为水平方向
  bool get isVerticalDirection =>
      ((angle.value % (2 * math.pi)) / (math.pi / 2)).round() % 4 == 1 ||
      ((angle.value % (2 * math.pi)) / (math.pi / 2)).round() % 4 == 3;
}

// use fullscreen with controller provider

class DesktopFullscreen extends StatelessWidget {
  const DesktopFullscreen({super.key, required this.controller});
  final VideoController controller;

  @override
  Widget build(BuildContext context) {
    return Material(
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        body: Stack(
          fit: StackFit.expand, // 使Stack填充整个父容器
          children: [
            Container(
              color: Colors.black, // 设置你想要的背景色
            ),
            Obx(
              () => Transform.scale(
                scale: controller.isVerticalDirection ? 9 / 16 : 1,
                child: Transform.rotate(
                  angle: controller.angle.value,
                  child: media_kit_video.Video(
                    controller: controller.mediaPlayerController,
                    fit: controller.settings.videofitArrary[controller.videoFitIndex.value],
                    controls: null,
                  ),
                ),
              ),
            ),
            VideoControllerPanel(controller: controller),
          ],
        ),
      ),
    );
  }
}
