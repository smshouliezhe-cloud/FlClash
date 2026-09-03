class ChainProxySettings {
  final bool enabled;
  final String server;
  final int port;
  final String username;
  final String password;
  final bool udp;

  const ChainProxySettings({
    this.enabled = false,
    this.server = '',
    this.port = 0,
    this.username = '',
    this.password = '',
    this.udp = true,
  });

  bool get isComplete =>
      server.trim().isNotEmpty && port > 0 && port <= 65535;

  ChainProxySettings copyWith({
    bool? enabled,
    String? server,
    int? port,
    String? username,
    String? password,
    bool? udp,
  }) {
    return ChainProxySettings(
      enabled: enabled ?? this.enabled,
      server: server ?? this.server,
      port: port ?? this.port,
      username: username ?? this.username,
      password: password ?? this.password,
      udp: udp ?? this.udp,
    );
  }

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'server': server,
    'port': port,
    'username': username,
    'password': password,
    'udp': udp,
  };

  factory ChainProxySettings.fromJson(Map<String, Object?> json) {
    return ChainProxySettings(
      enabled: json['enabled'] == true,
      server: json['server'] as String? ?? '',
      port: (json['port'] as num?)?.toInt() ?? 0,
      username: json['username'] as String? ?? '',
      password: json['password'] as String? ?? '',
      udp: json['udp'] != false,
    );
  }
}
