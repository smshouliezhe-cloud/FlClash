import 'package:fl_clash/common/chain_proxy.dart';
import 'package:fl_clash/models/chain_proxy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

void main() {
  test('strict DNS mode removes inherited plaintext and bypass resolvers', () {
    const source = '''
mode: rule
dns:
  enable: true
  nameserver:
    - 223.5.5.5
  default-nameserver:
    - 114.114.114.114
  fallback:
    - 8.8.4.4
  fallback-filter:
    geoip: true
  nameserver-policy:
    '+.example.com': 1.1.1.1
  proxy-server-nameserver-policy:
    '+.node.example': 9.9.9.9
  direct-nameserver:
    - system
  direct-nameserver-follow-policy: true
proxies:
  - name: Airport-A
    type: ss
    server: node.example
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
      dnsLeakProtection: true,
    );

    final parsed = loadYaml(applyChainProxyYaml(source, settings, 77));
    final dns = parsed['dns'] as YamlMap;

    expect(dns['enable'], true);
    expect(dns['respect-rules'], true);
    expect(dns['prefer-h3'], false);
    expect(dns['use-system-hosts'], false);
    expect(
      (dns['nameserver'] as YamlList).map((item) => item.toString()).toList(),
      [
        'https://1.1.1.1/dns-query#RULES',
        'https://8.8.8.8/dns-query#RULES',
      ],
    );
    expect(
      (dns['proxy-server-nameserver'] as YamlList)
          .map((item) => item.toString())
          .toList(),
      [
        'https://1.1.1.1/dns-query',
        'https://8.8.8.8/dns-query',
      ],
    );
    expect(
      (dns['default-nameserver'] as YamlList)
          .map((item) => item.toString())
          .toList(),
      [
        'https://1.1.1.1/dns-query',
        'https://8.8.8.8/dns-query',
      ],
    );

    for (final key in const [
      'fallback',
      'fallback-filter',
      'nameserver-policy',
      'proxy-server-nameserver-policy',
      'direct-nameserver',
      'direct-nameserver-follow-policy',
    ]) {
      expect(dns.containsKey(key), false, reason: '$key must not bypass strict DNS');
    }
  });
}
