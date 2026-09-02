import 'package:fl_clash/common/chain_proxy.dart';
import 'package:fl_clash/models/chain_proxy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

Map<String, dynamic> _normalize(Object? value) {
  if (value is YamlMap) {
    return {
      for (final entry in value.entries)
        entry.key.toString(): entry.value is YamlMap
            ? _normalize(entry.value)
            : entry.value is YamlList
            ? [for (final item in entry.value as YamlList) item]
            : entry.value,
    };
  }
  throw StateError('not a map');
}

void main() {
  const source = '''
mode: rule
proxies:
  - name: Airport-A
    type: ss
    server: 127.0.0.1
    port: 10001
    cipher: aes-128-gcm
    password: test
  - name: Airport-B
    type: ss
    server: 127.0.0.1
    port: 10002
    cipher: aes-128-gcm
    password: test
proxy-groups:
  - name: Proxy
    type: select
    proxies:
      - Airport-A
      - Airport-B
rules:
  - MATCH,Proxy
''';

  test('disabled settings leave yaml untouched', () {
    const settings = ChainProxySettings();
    expect(applyChainProxyYaml(source, settings, 1), source);
  });

  test('residential socks5 uses airport selector group as dialer', () {
    const settings = ChainProxySettings(
      enabled: true,
      sourceGroup: 'Proxy',
      server: '10.0.0.8',
      port: 1080,
      username: 'user',
      password: 'pass',
      udp: true,
      strict: true,
    );
    final output = applyChainProxyYaml(source, settings, 42);
    final map = _normalize(loadYaml(output));
    final proxies = map['proxies'] as List<dynamic>;
    final exit = proxies
        .whereType<YamlMap>()
        .firstWhere((item) => item['name'] == '__FLCLASH_CHAIN_EXIT_42');
    expect(exit['type'], 'socks5');
    expect(exit['server'], '10.0.0.8');
    expect(exit['port'], 1080);
    expect(exit['username'], 'user');
    expect(exit['password'], 'pass');
    expect(exit['udp'], true);
    expect(exit['dialer-proxy'], 'Proxy');
    expect(map['mode'], 'rule');
    final rules = loadYaml(output)['rules'] as YamlList;
    expect(rules, ['MATCH,__FLCLASH_CHAIN_EXIT_42']);
  });

  test('a fixed node is rejected because the chain must follow a group', () {
    const settings = ChainProxySettings(
      enabled: true,
      sourceGroup: 'Airport-A',
      server: '10.0.0.8',
      port: 1080,
    );
    expect(
      () => applyChainProxyYaml(source, settings, 1),
      throwsA(isA<StateError>()),
    );
  });

  test('missing airport group fails instead of falling back', () {
    const settings = ChainProxySettings(
      enabled: true,
      sourceGroup: 'Deleted-Group',
      server: '10.0.0.8',
      port: 1080,
    );
    expect(
      () => applyChainProxyYaml(source, settings, 1),
      throwsA(isA<StateError>()),
    );
  });

  test('legacy sourceProxy preference migrates to sourceGroup', () {
    final settings = ChainProxySettings.fromJson({
      'enabled': true,
      'sourceProxy': 'Proxy',
      'server': '10.0.0.8',
      'port': 1080,
    });
    expect(settings.sourceGroup, 'Proxy');
  });
}
