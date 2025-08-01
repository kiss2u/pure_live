enum LiveStatus { live, offline, replay, unknown, banned }

class LiveRoom {
  String? roomId;
  String? userId = '';
  String? link = '';
  String? title = '';
  String? nick = '';
  String? avatar = '';
  String? cover = '';
  String? area = '';
  String? watching = '';
  String? followers = '';
  String? platform = 'UNKNOWN';

  /// 介绍
  String? introduction;

  /// 公告
  String? notice;

  /// 状态
  bool? status;

  /// 附加信息
  dynamic data;

  /// 弹幕附加信息
  dynamic danmakuData;

  /// 是否录播
  bool? isRecord = false;
  // 直播状态
  LiveStatus? liveStatus = LiveStatus.offline;

  // 添加未命名的默认构造函数
  LiveRoom({
    this.roomId,
    this.userId,
    this.link,
    this.title = '',
    this.nick = '',
    this.avatar = '',
    this.cover = '',
    this.area,
    this.watching = '0',
    this.followers = '0',
    this.platform,
    this.liveStatus,
    this.data,
    this.danmakuData,
    this.isRecord = false,
    this.status = false,
    this.notice,
    this.introduction,
  });

  LiveRoom.fromJson(Map<String, dynamic> json)
    : roomId = json['roomId'] ?? '',
      userId = json['userId'] ?? '',
      title = json['title'] ?? '',
      link = json['link'] ?? '',
      nick = json['nick'] ?? '',
      avatar = json['avatar'] ?? '',
      cover = json['cover'] ?? '',
      area = json['area'] ?? '',
      watching = json['watching'] ?? '',
      followers = json['followers'] ?? '',
      platform = json['platform'] ?? '',
      liveStatus = LiveStatus.values[json['liveStatus'] ?? 1],
      status = json['status'] ?? false,
      notice = json['notice'] ?? '',
      introduction = json['introduction'] ?? '',
      isRecord = json['isRecord'] ?? false;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'roomId': roomId,
    'userId': userId,
    'title': title,
    'nick': nick,
    'avatar': avatar,
    'cover': cover,
    'area': area,
    'watching': watching,
    'followers': followers,
    'platform': platform,
    'liveStatus': liveStatus?.index ?? 1,
    'isRecord': isRecord,
    'status': status,
    'notice': notice,
    'introduction': introduction,
  };

  /// 创建一个新的LiveRoom实例，并用提供的值更新指定字段
  LiveRoom copyWith({
    String? roomId,
    String? userId,
    String? link,
    String? title,
    String? nick,
    String? avatar,
    String? cover,
    String? area,
    String? watching,
    String? followers,
    String? platform,
    String? introduction,
    String? notice,
    bool? status,
    dynamic data,
    dynamic danmakuData,
    bool? isRecord,
    LiveStatus? liveStatus,
  }) {
    return LiveRoom(
      roomId: roomId ?? this.roomId,
      userId: userId ?? this.userId,
      link: link ?? this.link,
      title: title ?? this.title,
      nick: nick ?? this.nick,
      avatar: avatar ?? this.avatar,
      cover: cover ?? this.cover,
      area: area ?? this.area,
      watching: watching ?? this.watching,
      followers: followers ?? this.followers,
      platform: platform ?? this.platform,
      introduction: introduction ?? this.introduction,
      notice: notice ?? this.notice,
      status: status ?? this.status,
      data: data ?? this.data,
      danmakuData: danmakuData ?? this.danmakuData,
      isRecord: isRecord ?? this.isRecord,
      liveStatus: liveStatus ?? this.liveStatus,
    );
  }

  @override
  bool operator ==(covariant LiveRoom other) => platform == other.platform && roomId == other.roomId;

  @override
  int get hashCode => Object.hash(platform, roomId);
}
