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
  - name: Proxy
    type: select
    proxies:
      - Airport-A
      - Airport-B
rules:
  - DOMAIN-SUFFIX,example.cn,DIRECT
  - MATCH,Proxy
''';

  test('disabled settings leave yaml untouched', () {
    const settings = ChainProxySettings();
    expect(applyChainProxyYaml(source, settings, 1), source);
  });

  test('DNS protection splits proxy bootstrap from protected queries', () {
    const settings = ChainProxySettings(
      enabled: true,
      server: '10.0.0.8',
      port: 1080,
    );
    final parsed = loadYaml(applyChainProxyYaml(source, settings, 42));
    final dns = parsed['dns'] as YamlMap;

    expect(dns['enable'], true);
    expect(dns['respect-rules'], true);
    expect(dns['prefer-h3'], false);
    expect(dns['use-system-hosts'], false);
    expect(
      (dns['nameserver'] as YamlList).map((item) => item.toString()).toList(),
      ['https://1.1.1.1/dns-query', 'https://8.8.8.8/dns-query'],
    );
    expect(
      (dns['proxy-server-nameserver'] as YamlList)
          .map((item) => item.toString())
          .toList(),
      [
        'https://doh.pub/dns-query#DIRECT',
        'https://dns.alidns.com/dns-query#DIRECT',
      ],
    );
    expect(
      (dns['default-nameserver'] as YamlList)
          .map((item) => item.toString())
          .toList(),
      ['223.5.5.5', '119.29.29.29'],
    );
  });

  test('DNS protection removes inherited resolver bypasses', () {
    const sourceWithDns = '''
mode: rule
dns:
  enable: true
  nameserver:
    - 192.0.2.53
  fallback:
    - 114.114.114.114
  direct-nameserver:
    - system
  nameserver-policy:
    '+.example.com': 192.0.2.53
proxies:
  - name: Airport-A
    type: ss
    server: airport.example
    port: 10001
    cipher: aes-128-gcm
    password: test
rules:
  - MATCH,Airport-A
''';
    const settings = ChainProxySettings(
      enabled: true,
      server: 'residential.example',
      port: 1080,
    );
    final parsed = loadYaml(applyChainProxyYaml(sourceWithDns, settings, 43));
    final dns = parsed['dns'] as YamlMap;

    expect(dns.containsKey('fallback'), false);
    expect(dns.containsKey('direct-nameserver'), false);
    expect(dns.containsKey('nameserver-policy'), false);
    expect(
      (dns['nameserver'] as YamlList).map((item) => item.toString()).toList(),
      ['https://1.1.1.1/dns-query', 'https://8.8.8.8/dns-query'],
    );
    expect(
      (dns['proxy-server-nameserver'] as YamlList)
          .map((item) => item.toString())
          .toList(),
      [
        'https://doh.pub/dns-query#DIRECT',
        'https://dns.alidns.com/dns-query#DIRECT',
      ],
    );
    expect(dns.toString(), isNot(contains('192.0.2.53')));
    expect(dns.toString(), isNot(contains('114.114.114.114')));
  });

  test('DNS protection can be disabled without rewriting DNS', () {
    const sourceWithDns = '''
mode: rule
dns:
  enable: true
  nameserver:
    - 192.0.2.53
proxies:
  - name: Airport-A
    type: ss
    server: 127.0.0.1
    port: 10001
    cipher: aes-128-gcm
    password: test
rules:
  - MATCH,Airport-A
''';
    const settings = ChainProxySettings(
      enabled: true,
      server: '10.0.0.8',
      port: 1080,
      dnsLeakProtection: false,
    );
    final parsed = loadYaml(applyChainProxyYaml(sourceWithDns, settings, 44));
    final dns = parsed['dns'] as YamlMap;
    expect(dns['nameserver'], ['192.0.2.53']);
    expect(dns.containsKey('respect-rules'), false);
  });

  test('visible airport nodes become residential landing chains', () {
    const settings = ChainProxySettings(
      enabled: true,
      server: '10.0.0.8',
      port: 1080,
      username: 'user',
      password: 'pass',
      udp: true,
    );
    final parsed = loadYaml(applyChainProxyYaml(source, settings, 45));
    final proxies = (parsed['proxies'] as YamlList).whereType<YamlMap>().toList();
    final airportA = proxies.firstWhere((item) => item['name'] == 'Airport-A');

    expect(airportA['type'], 'socks5');
    expect(airportA['server'], '10.0.0.8');
    expect(airportA['port'], 1080);
    expect(airportA['username'], 'user');
    expect(airportA['password'], 'pass');
    expect(airportA['udp'], true);
    expect(
      airportA['dialer-proxy'].toString(),
      startsWith('__FLCLASH_CHAIN_UPSTREAM_45_'),
    );
  });

  test('provider-backed rules use compatibility landing wrapper', () {
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
    final parsed = loadYaml(applyChainProxyYaml(providerSource, settings, 46));
    final rules = parsed['rules'] as YamlList;
    expect(rules[0], 'DOMAIN-SUFFIX,example.cn,DIRECT');
    expect(rules[1].toString(), startsWith('MATCH,__FLCLASH_CHAIN_EXIT_46_'));
  });

  test('old saved settings default DNS protection to enabled', () {
    final settings = ChainProxySettings.fromJson({
      'enabled': true,
      'server': '10.0.0.8',
      'port': 1080,
      'udp': false,
    });
    expect(settings.dnsLeakProtection, true);
    expect(settings.isComplete, true);
  });
}
