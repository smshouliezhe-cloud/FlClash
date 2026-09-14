import 'package:fl_clash/common/chain_proxy.dart';
import 'package:fl_clash/models/chain_proxy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

void main() {
  const source = '''
mode: rule
tun:
  enable: true
  stack: mixed
  auto-route: true
  dns-hijack:
    - any:53
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
proxy-groups:
  - name: Proxy
    type: select
    proxies:
      - Airport-A
      - DIRECT
rules:
  - GEOIP,CN,DIRECT
  - MATCH,Proxy
''';

  test('strict Android privacy owns TUN DNS and UDP egress', () {
    const settings = ChainProxySettings(
      enabled: true,
      server: '10.0.0.8',
      port: 1080,
      udp: true,
      dnsLeakProtection: true,
    );

    final parsed = loadYaml(
      applyChainProxyYaml(
        source,
        settings,
        77,
        enforceAndroidPrivacy: true,
      ),
    );
    final dns = parsed['dns'] as YamlMap;
    final tun = parsed['tun'] as YamlMap;
    final rules = parsed['rules'] as YamlList;
    final groups = parsed['proxy-groups'] as YamlList;
    final privacyGroup = chainProxyPrivacyGroupName(77);

    expect(tun['enable'], true);
    expect(tun['strict-route'], true);
    expect(
      (tun['dns-hijack'] as YamlList).map((item) => item.toString()).toList(),
      containsAll(<String>['any:53', 'tcp://any:53']),
    );

    expect(dns['enable'], true);
    expect(dns['respect-rules'], false);
    expect(dns['prefer-h3'], false);
    expect(dns['use-system-hosts'], false);
    expect(
      (dns['nameserver'] as YamlList).map((item) => item.toString()).toList(),
      [
        'https://doh.pub/dns-query#$privacyGroup',
        'https://dns.alidns.com/dns-query#$privacyGroup',
      ],
    );
    expect(
      (dns['proxy-server-nameserver'] as YamlList)
          .map((item) => item.toString())
          .toList(),
      ['https://doh.pub/dns-query', 'https://dns.alidns.com/dns-query'],
    );
    expect(
      (dns['default-nameserver'] as YamlList)
          .map((item) => item.toString())
          .toList(),
      [
        'https://223.5.5.5/dns-query',
        'https://223.6.6.6/dns-query',
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

    expect(rules[0], 'NETWORK,udp,$privacyGroup');
    expect(rules[1], 'DST-PORT,853,REJECT');
    expect(
      groups.whereType<YamlMap>().any(
        (group) => group['name'] == privacyGroup && group['hidden'] == true,
      ),
      true,
    );
  });

  test('UDP disabled rejects instead of falling through to DIRECT', () {
    const settings = ChainProxySettings(
      enabled: true,
      server: '10.0.0.8',
      port: 1080,
      udp: false,
      dnsLeakProtection: true,
    );

    final parsed = loadYaml(
      applyChainProxyYaml(
        source,
        settings,
        78,
        enforceAndroidPrivacy: true,
      ),
    );
    final rules = parsed['rules'] as YamlList;
    expect(rules[0], 'NETWORK,udp,REJECT');
    expect(rules[1], 'DST-PORT,853,REJECT');
  });

  test('strict Android privacy refuses to run without TUN', () {
    const sourceWithoutTun = '''
mode: rule
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

    expect(
      () => applyChainProxyYaml(
        sourceWithoutTun,
        settings,
        79,
        enforceAndroidPrivacy: true,
      ),
      throwsA(isA<StateError>()),
    );
  });
}
