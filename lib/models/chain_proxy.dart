enum ChainProxyAppMode {
  all,
  selected;

  static ChainProxyAppMode fromJson(Object? value) {
    return switch (value) {
      'selected' => ChainProxyAppMode.selected,
      _ => ChainProxyAppMode.all,
    };
  }
}

class ChainProxySettings {
  final bool enabled;
  final String sourceGroup;
  final String server;
  final int port;
  final String username;
  final String password;
  final bool udp;
  final bool strict;
  final ChainProxyAppMode appMode;
  final List<String> appPackages;

  const ChainProxySettings({
    this.enabled = false,
    this.sourceGroup = '',
    this.server = '',
    this.port = 0,
    this.username = '',
    this.password = '',
    this.udp = true,
    this.strict = true,
    this.appMode = ChainProxyAppMode.all,
    this.appPackages = const [],
  });

  bool get isComplete =>
      sourceGroup.trim().isNotEmpty &&
      server.trim().isNotEmpty &&
      port > 0 &&
      port <= 65535;

  ChainProxySettings copyWith({
    bool? enabled,
    String? sourceGroup,
    String? server,
    int? port,
    String? username,
    String? password,
    bool? udp,
    bool? strict,
    ChainProxyAppMode? appMode,
    List<String>? appPackages,
  }) {
    return ChainProxySettings(
      enabled: enabled ?? this.enabled,
      sourceGroup: sourceGroup ?? this.sourceGroup,
      server: server ?? this.server,
      port: port ?? this.port,
      username: username ?? this.username,
      password: password ?? this.password,
      udp: udp ?? this.udp,
      strict: strict ?? this.strict,
      appMode: appMode ?? this.appMode,
      appPackages: appPackages ?? this.appPackages,
    );
  }

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'sourceGroup': sourceGroup,
    'server': server,
    'port': port,
    'username': username,
    'password': password,
    'udp': udp,
    'strict': strict,
    'appMode': appMode.name,
    'appPackages': appPackages,
  };

  factory ChainProxySettings.fromJson(Map<String, Object?> json) {
    final rawPackages = json['appPackages'];
    final appPackages = rawPackages is List
        ? rawPackages
              .whereType<Object>()
              .map((item) => item.toString().trim())
              .where((item) => item.isNotEmpty)
              .toSet()
              .toList()
        : <String>[];
    return ChainProxySettings(
      enabled: json['enabled'] == true,
      // sourceProxy is kept as a one-time compatibility fallback for builds
      // produced before chain routing was changed from a fixed node to a
      // selector group.
      sourceGroup:
          json['sourceGroup'] as String? ?? json['sourceProxy'] as String? ?? '',
      server: json['server'] as String? ?? '',
      port: (json['port'] as num?)?.toInt() ?? 0,
      username: json['username'] as String? ?? '',
      password: json['password'] as String? ?? '',
      udp: json['udp'] != false,
      strict: json['strict'] != false,
      appMode: ChainProxyAppMode.fromJson(json['appMode']),
      appPackages: appPackages,
    );
  }
}
