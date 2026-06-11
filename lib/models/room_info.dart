class RoomInfo {
  final String code;
  final String hostIp;
  final String? hostName;
  final String? hostAvatarBase64;

  const RoomInfo({
    required this.code,
    required this.hostIp,
    this.hostName,
    this.hostAvatarBase64,
  });
}
