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
  - name: Other
    type: select
    proxies:
      - Airport-B
  - name: Unused
    type: select
    proxies:
      - Airport-A
rules:
  - DOMAIN-SUFFIX,example.cn,DIRECT
  - DOMAIN-SUFFIX,blocked.example,REJECT
  - RULE-SET,foreign,Proxy,no-resolve
  - DOMAIN-SUFFIX,other.example,Other
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
  });

  test('chain follows original subscription rules', () {
    const settings = ChainProxySettings(
      enabled: true,
      sourceGroup: 'Proxy',
      server: '10.0.0.8',
      port: 1080,
    );
    final output = applyChainProxyYaml(source, settings, 7);
    final parsed = loadYaml(output);
    final rules = parsed['rules'] as YamlList;

    expect(parsed['mode'], 'rule');
    expect(
      rules,
      [
        'DOMAIN-SUFFIX,example.cn,DIRECT',
        'DOMAIN-SUFFIX,blocked.example,REJECT',
        'RULE-SET,foreign,__FLCLASH_CHAIN_EXIT_7,no-resolve',
        'DOMAIN-SUFFIX,other.example,Other',
        'MATCH,__FLCLASH_CHAIN_EXIT_7',
      ],
    );
  });

  test('rules unrelated to selected airport group are preserved', () {
    const settings = ChainProxySettings(
      enabled: true,
      sourceGroup: 'Other',
      server: '10.0.0.8',
      port: 1080,
    );
    final output = applyChainProxyYaml(source, settings, 8);
    final rules = loadYaml(output)['rules'] as YamlList;
    expect(rules[0], 'DOMAIN-SUFFIX,example.cn,DIRECT');
    expect(rules[2], 'RULE-SET,foreign,Proxy,no-resolve');
    expect(rules[3], 'DOMAIN-SUFFIX,other.example,__FLCLASH_CHAIN_EXIT_8');
    expect(rules[4], 'MATCH,Proxy');
  });

  test('profile without rules fails instead of silently becoming global', () {
    const noRulesSource = '''
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
''';
    const settings = ChainProxySettings(
      enabled: true,
      sourceGroup: 'Proxy',
      server: '10.0.0.8',
      port: 1080,
    );
    expect(
      () => applyChainProxyYaml(noRulesSource, settings, 9),
      throwsA(isA<StateError>()),
    );
  });

  test('group not referenced by any rule fails visibly', () {
    const settings = ChainProxySettings(
      enabled: true,
      sourceGroup: 'Unused',
      server: '10.0.0.8',
      port: 1080,
    );
    expect(
      () => applyChainProxyYaml(source, settings, 10),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('未引用机场代理组'),
        ),
      ),
    );
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
