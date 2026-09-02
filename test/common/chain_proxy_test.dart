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
proxy-groups:
  - name: Proxy
    type: select
    proxies:
      - Airport-A
rules:
  - MATCH,Proxy
''';

  test('disabled settings leave yaml untouched', () {
    const settings = ChainProxySettings();
    expect(applyChainProxyYaml(source, settings, 1), source);
  });

  test('injects residential socks5 with airport dialer proxy', () {
    const settings = ChainProxySettings(
      enabled: true,
      sourceProxy: 'Airport-A',
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
    expect(exit['dialer-proxy'], 'Airport-A');
    expect(map['mode'], 'rule');
    final rules = loadYaml(output)['rules'] as YamlList;
    expect(rules, ['MATCH,__FLCLASH_CHAIN_EXIT_42']);
  });

  test('missing airport source fails instead of falling back', () {
    const settings = ChainProxySettings(
      enabled: true,
      sourceProxy: 'Deleted-Airport',
      server: '10.0.0.8',
      port: 1080,
    );
    expect(
      () => applyChainProxyYaml(source, settings, 1),
      throwsA(isA<StateError>()),
    );
  });
}
