class Device {
  final String name;
  final String ip;
  final int port;

  const Device({required this.name, required this.ip, required this.port});

  @override
  String toString() => '$name ($ip:$port)';
}
