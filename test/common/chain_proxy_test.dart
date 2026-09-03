import 'package:fl_clash/common/chain_proxy.dart';
import 'package:fl_clash/models/chain_proxy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

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
  - name: 🇭🇰 香港节点
    type: select
    proxies:
      - Airport-A
      - Airport-B
  - name: Proxy
    type: select
    proxies:
      - 🇭🇰 香港节点
      - Airport-B
  - name: Other
    type: select
    proxies:
      - Airport-B
rules:
  - DOMAIN-SUFFIX,example.cn,DIRECT
  - DOMAIN-SUFFIX,blocked.example,REJECT
  - RULE-SET,foreign,Proxy,no-resolve
  - DOMAIN-SUFFIX,other.example,Other
  - DOMAIN,api.example,Airport-A
  - MATCH,Proxy
''';

  test('disabled settings leave yaml untouched', () {
    const settings = ChainProxySettings();
    expect(applyChainProxyYaml(source, settings, 1), source);
  });

  test('every real rule proxy target gets its own residential chain', () {
    const settings = ChainProxySettings(
      enabled: true,
      server: '10.0.0.8',
      port: 1080,
      username: 'user',
      password: 'pass',
      udp: true,
    );
    final output = applyChainProxyYaml(source, settings, 42);
    final parsed = loadYaml(output);
    final proxies = parsed['proxies'] as YamlList;

    final chainExits = proxies.whereType<YamlMap>().where(
      (item) => item['name'].toString().startsWith('__FLCLASH_CHAIN_EXIT_42_'),
    );
    expect(chainExits.length, 3);
    expect(
      chainExits.map((item) => item['dialer-proxy']).toSet(),
      {'Airport-A', 'Other', 'Proxy'},
    );
    for (final exit in chainExits) {
      expect(exit['type'], 'socks5');
      expect(exit['server'], '10.0.0.8');
      expect(exit['port'], 1080);
      expect(exit['username'], 'user');
      expect(exit['password'], 'pass');
      expect(exit['udp'], true);
    }
  });

  test('DIRECT and REJECT stay unchanged while proxy rules are chained', () {
    const settings = ChainProxySettings(
      enabled: true,
      server: '10.0.0.8',
      port: 1080,
    );
    final output = applyChainProxyYaml(source, settings, 7);
    final parsed = loadYaml(output);
    final rules = parsed['rules'] as YamlList;

    expect(parsed['mode'], 'rule');
    expect(rules[0], 'DOMAIN-SUFFIX,example.cn,DIRECT');
    expect(rules[1], 'DOMAIN-SUFFIX,blocked.example,REJECT');
    expect(rules[2].toString(), contains('__FLCLASH_CHAIN_EXIT_7_'));
    expect(rules[2].toString(), endsWith(',no-resolve'));
    expect(rules[3].toString(), contains('__FLCLASH_CHAIN_EXIT_7_'));
    expect(rules[4].toString(), contains('__FLCLASH_CHAIN_EXIT_7_'));
    expect(rules[5].toString(), contains('__FLCLASH_CHAIN_EXIT_7_'));
  });

  test('nested country selector does not need to be referenced by rules', () {
    const settings = ChainProxySettings(
      enabled: true,
      server: '10.0.0.8',
      port: 1080,
    );
    final output = applyChainProxyYaml(source, settings, 8);
    final parsed = loadYaml(output);
    final groups = parsed['proxy-groups'] as YamlList;
    final proxyGroup = groups
        .whereType<YamlMap>()
        .firstWhere((item) => item['name'] == 'Proxy');

    // The subscription hierarchy remains intact: rules still conceptually use
    // Proxy, and Proxy can keep selecting the nested Hong Kong group. The
    // residential outbound simply dials through Proxy's current selection.
    expect(proxyGroup['proxies'], contains('🇭🇰 香港节点'));

    final exits = (parsed['proxies'] as YamlList)
        .whereType<YamlMap>()
        .where((item) => item['dialer-proxy'] == 'Proxy')
        .toList();
    expect(exits, hasLength(1));
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
''';
    const settings = ChainProxySettings(
      enabled: true,
      server: '10.0.0.8',
      port: 1080,
    );
    expect(
      () => applyChainProxyYaml(noRulesSource, settings, 9),
      throwsA(isA<StateError>()),
    );
  });

  test('DIRECT-only rules fail visibly because there is nothing to chain', () {
    const directOnlySource = '''
mode: rule
proxies:
  - name: Airport-A
    type: ss
    server: 127.0.0.1
    port: 10001
    cipher: aes-128-gcm
    password: test
rules:
  - MATCH,DIRECT
''';
    const settings = ChainProxySettings(
      enabled: true,
      server: '10.0.0.8',
      port: 1080,
    );
    expect(
      () => applyChainProxyYaml(directOnlySource, settings, 10),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('没有可链式代理的代理目标'),
        ),
      ),
    );
  });

  test('old saved group/app fields are ignored during migration', () {
    final settings = ChainProxySettings.fromJson({
      'enabled': true,
      'sourceGroup': '🇭🇰 香港节点',
      'appMode': 'selected',
      'appPackages': ['com.example.old'],
      'server': '10.0.0.8',
      'port': 1080,
      'udp': false,
    });
    expect(settings.enabled, true);
    expect(settings.server, '10.0.0.8');
    expect(settings.port, 1080);
    expect(settings.udp, false);
    expect(settings.isComplete, true);
  });
}
