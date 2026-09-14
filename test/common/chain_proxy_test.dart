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

  test('DNS protection uses encrypted resolvers and encrypted bootstrap', () {
    const settings = ChainProxySettings(enabled: true, server: '10.0.0.8', port: 1080);
    final parsed = loadYaml(applyChainProxyYaml(source, settings, 42));
    final dns = parsed['dns'] as YamlMap;
    expect(dns['enable'], true);
    expect(dns['listen'], '0.0.0.0:1053');
    expect(dns['respect-rules'], false);
    expect(dns['prefer-h3'], false);
    expect(dns['use-system-hosts'], false);
    expect(dns['enhanced-mode'], 'fake-ip');
    expect(dns['fake-ip-range'], '198.18.0.1/16');
    expect((dns['nameserver'] as YamlList).map((e) => e.toString()).toList(), ['https://doh.pub/dns-query', 'https://dns.alidns.com/dns-query']);
    expect((dns['default-nameserver'] as YamlList).map((e) => e.toString()).toList(), ['https://223.5.5.5/dns-query', 'https://223.6.6.6/dns-query']);
  });

  test('visible airport nodes become residential landing chains', () {
    const settings = ChainProxySettings(enabled: true, server: '10.0.0.8', port: 1080, username: 'user', password: 'pass');
    final parsed = loadYaml(applyChainProxyYaml(source, settings, 45));
    final proxies = (parsed['proxies'] as YamlList).whereType<YamlMap>().toList();
    final airportA = proxies.firstWhere((item) => item['name'] == 'Airport-A');
    expect(airportA['type'], 'socks5');
    expect(airportA['server'], '10.0.0.8');
    expect(airportA['dialer-proxy'].toString(), startsWith('__FLCLASH_CHAIN_UPSTREAM_45_'));
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
    const settings = ChainProxySettings(enabled: true, server: '10.0.0.8', port: 1080);
    final parsed = loadYaml(applyChainProxyYaml(providerSource, settings, 46));
    final rules = parsed['rules'] as YamlList;
    expect(rules[0], 'DOMAIN-SUFFIX,example.cn,DIRECT');
    expect(rules[1].toString(), startsWith('MATCH,__FLCLASH_CHAIN_EXIT_46_'));
  });

  test('old saved settings default DNS protection to enabled', () {
    final settings = ChainProxySettings.fromJson({'enabled': true, 'server': '10.0.0.8', 'port': 1080, 'udp': false});
    expect(settings.dnsLeakProtection, true);
    expect(settings.isComplete, true);
  });
}
