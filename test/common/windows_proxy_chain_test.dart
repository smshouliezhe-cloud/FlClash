import 'package:fl_clash/common/chain_proxy.dart';
import 'package:fl_clash/models/chain_proxy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

Object? normalize(Object? value) {
  if (value is YamlMap) {
    return <String, dynamic>{
      for (final entry in value.entries)
        entry.key.toString(): normalize(entry.value),
    };
  }
  if (value is YamlList) return value.map(normalize).toList();
  return value;
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
    password: test-a
  - name: Airport-B
    type: ss
    server: 127.0.0.1
    port: 10002
    cipher: aes-128-gcm
    password: test-b
proxy-groups:
  - name: Proxy
    type: select
    proxies:
      - Airport-A
      - Airport-B
rules:
  - DOMAIN-SUFFIX,example.cn,DIRECT
  - MATCH,Proxy
''';

  const settings = ChainProxySettings(
    enabled: true,
    server: '10.0.0.8',
    port: 1080,
    username: 'res-user',
    password: 'res-pass',
    udp: true,
  );

  test('Windows uses the same residential landing chain as Android', () {
    final parsed = loadYaml(applyChainProxyYaml(source, settings, 77));
    final proxies = (parsed['proxies'] as YamlList).whereType<YamlMap>().toList();

    final airportA = proxies.firstWhere((item) => item['name'] == 'Airport-A');
    expect(airportA['type'], 'socks5');
    expect(airportA['server'], '10.0.0.8');
    expect(airportA['port'], 1080);
    expect(airportA['username'], 'res-user');
    expect(airportA['password'], 'res-pass');
    expect(airportA['udp'], true);

    final hiddenUpstreamName = airportA['dialer-proxy'].toString();
    expect(hiddenUpstreamName, startsWith('__FLCLASH_CHAIN_UPSTREAM_77_'));

    final hiddenUpstream = proxies.firstWhere(
      (item) => item['name'] == hiddenUpstreamName,
    );
    expect(hiddenUpstream['type'], 'ss');
    expect(hiddenUpstream['server'], '127.0.0.1');
    expect(hiddenUpstream['port'], 10001);
  });

  test('ordinary Windows proxy selection stays unchanged', () {
    final before = normalize(loadYaml(source)) as Map<String, dynamic>;
    final after = normalize(
      loadYaml(applyChainProxyYaml(source, settings, 78)),
    ) as Map<String, dynamic>;

    expect(after['rules'], before['rules']);
    expect(after['proxy-groups'], before['proxy-groups']);
    expect(after['mode'], before['mode']);
  });

  test('each airport node gets its own residential landing wrapper', () {
    final parsed = loadYaml(applyChainProxyYaml(source, settings, 79));
    final proxies = (parsed['proxies'] as YamlList).whereType<YamlMap>().toList();

    final airportA = proxies.firstWhere((item) => item['name'] == 'Airport-A');
    final airportB = proxies.firstWhere((item) => item['name'] == 'Airport-B');

    expect(airportA['type'], 'socks5');
    expect(airportB['type'], 'socks5');
    expect(airportA['dialer-proxy'], isNot(airportB['dialer-proxy']));
  });

  test('disabled Windows residential chain leaves yaml untouched', () {
    expect(
      applyChainProxyYaml(source, const ChainProxySettings(), 80),
      source,
    );
  });
}
