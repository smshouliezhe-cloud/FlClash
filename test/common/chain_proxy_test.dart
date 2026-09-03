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
rules:
  - DOMAIN-SUFFIX,example.cn,DIRECT
  - DOMAIN-SUFFIX,blocked.example,REJECT
  - RULE-SET,foreign,Proxy,no-resolve
  - DOMAIN,api.example,Airport-A
  - MATCH,Proxy
''';

  test('disabled settings leave yaml untouched', () {
    const settings = ChainProxySettings();
    expect(applyChainProxyYaml(source, settings, 1), source);
  });

  test('ordinary subscription keeps rules and groups unchanged', () {
    const settings = ChainProxySettings(
      enabled: true,
      server: '10.0.0.8',
      port: 1080,
      username: 'user',
      password: 'pass',
      udp: true,
    );
    final original = loadYaml(source);
    final parsed = loadYaml(applyChainProxyYaml(source, settings, 42));

    expect(parsed['mode'], original['mode']);
    expect(parsed['rules'].toString(), original['rules'].toString());
    expect(
      parsed['proxy-groups'].toString(),
      original['proxy-groups'].toString(),
    );
  });

  test('each visible airport node becomes a residential landing chain', () {
    const settings = ChainProxySettings(
      enabled: true,
      server: '10.0.0.8',
      port: 1080,
      username: 'user',
      password: 'pass',
      udp: true,
    );
    final parsed = loadYaml(applyChainProxyYaml(source, settings, 42));
    final proxies = (parsed['proxies'] as YamlList).whereType<YamlMap>().toList();

    final airportA = proxies.firstWhere((item) => item['name'] == 'Airport-A');
    final airportB = proxies.firstWhere((item) => item['name'] == 'Airport-B');
    expect(airportA['type'], 'socks5');
    expect(airportA['server'], '10.0.0.8');
    expect(airportA['port'], 1080);
    expect(airportA['username'], 'user');
    expect(airportA['password'], 'pass');
    expect(airportA['udp'], true);
    expect(
      airportA['dialer-proxy'].toString(),
      startsWith('__FLCLASH_CHAIN_UPSTREAM_42_'),
    );
    expect(
      airportB['dialer-proxy'].toString(),
      startsWith('__FLCLASH_CHAIN_UPSTREAM_42_'),
    );

    final upstreamA = proxies.firstWhere(
      (item) => item['name'] == airportA['dialer-proxy'],
    );
    expect(upstreamA['type'], 'ss');
    expect(upstreamA['server'], '127.0.0.1');
    expect(upstreamA['port'], 10001);
  });

  test('nested selectors automatically select chained leaf nodes', () {
    const settings = ChainProxySettings(
      enabled: true,
      server: '10.0.0.8',
      port: 1080,
    );
    final parsed = loadYaml(applyChainProxyYaml(source, settings, 8));
    final groups = (parsed['proxy-groups'] as YamlList).whereType<YamlMap>();
    final hongKong = groups.firstWhere((item) => item['name'] == '🇭🇰 香港节点');
    final proxy = groups.firstWhere((item) => item['name'] == 'Proxy');

    expect(hongKong['proxies'], ['Airport-A', 'Airport-B']);
    expect(proxy['proxies'], ['🇭🇰 香港节点', 'Airport-B']);

    final wrappers = (parsed['proxies'] as YamlList)
        .whereType<YamlMap>()
        .where((item) => item['name'] == 'Airport-A' || item['name'] == 'Airport-B')
        .toList();
    expect(wrappers, hasLength(2));
    expect(wrappers.every((item) => item['type'] == 'socks5'), true);
  });

  test('profile without rules still chains normal subscription nodes', () {
    const noRulesSource = '''
mode: global
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
      server: '10.0.0.8',
      port: 1080,
    );
    final parsed = loadYaml(applyChainProxyYaml(noRulesSource, settings, 9));
    expect(parsed['mode'], 'global');
    final airportA = (parsed['proxies'] as YamlList)
        .whereType<YamlMap>()
        .firstWhere((item) => item['name'] == 'Airport-A');
    expect(airportA['type'], 'socks5');
  });

  test('explicit direct proxy entries are not turned into residential chains', () {
    const directSource = '''
mode: rule
proxies:
  - name: MyDirect
    type: direct
  - name: Airport-A
    type: ss
    server: 127.0.0.1
    port: 10001
    cipher: aes-128-gcm
    password: test
rules:
  - DOMAIN-SUFFIX,lan.example,MyDirect
  - MATCH,Airport-A
''';
    const settings = ChainProxySettings(
      enabled: true,
      server: '10.0.0.8',
      port: 1080,
    );
    final parsed = loadYaml(applyChainProxyYaml(directSource, settings, 10));
    final proxies = (parsed['proxies'] as YamlList).whereType<YamlMap>().toList();
    expect(
      proxies.firstWhere((item) => item['name'] == 'MyDirect')['type'],
      'direct',
    );
    expect(
      proxies.firstWhere((item) => item['name'] == 'Airport-A')['type'],
      'socks5',
    );
    expect((parsed['rules'] as YamlList)[0], 'DOMAIN-SUFFIX,lan.example,MyDirect');
  });

  test('provider-backed groups use rule-target compatibility wrapper', () {
    const providerSource = '''
mode: rule
proxy-providers:
  airport:
    type: http
    url: https://example.com/sub
proxy-groups:
  - name: Proxy
    type: select
    use:
      - airport
rules:
  - DOMAIN-SUFFIX,example.cn,DIRECT
  - MATCH,Proxy
''';
    const settings = ChainProxySettings(
      enabled: true,
      server: '10.0.0.8',
      port: 1080,
    );
    final parsed = loadYaml(applyChainProxyYaml(providerSource, settings, 11));
    final rules = parsed['rules'] as YamlList;
    expect(rules[0], 'DOMAIN-SUFFIX,example.cn,DIRECT');
    expect(rules[1].toString(), startsWith('MATCH,__FLCLASH_CHAIN_EXIT_11_'));

    final exit = (parsed['proxies'] as YamlList)
        .whereType<YamlMap>()
        .firstWhere(
          (item) => item['name'].toString().startsWith('__FLCLASH_CHAIN_EXIT_11_'),
        );
    expect(exit['type'], 'socks5');
    expect(exit['dialer-proxy'], 'Proxy');
  });

  test('provider-backed profile without rules fails visibly', () {
    const providerSource = '''
mode: global
proxy-providers:
  airport:
    type: http
    url: https://example.com/sub
proxy-groups:
  - name: Proxy
    type: select
    use:
      - airport
''';
    const settings = ChainProxySettings(
      enabled: true,
      server: '10.0.0.8',
      port: 1080,
    );
    expect(
      () => applyChainProxyYaml(providerSource, settings, 12),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('动态代理源暂不支持无规则模式'),
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
