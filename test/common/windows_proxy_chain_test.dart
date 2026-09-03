import 'package:fl_clash/common/windows_proxy_chain.dart';
import 'package:fl_clash/models/windows_proxy_chain.dart';
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
  - name: Residential
    type: socks5
    server: 10.0.0.8
    port: 1080
proxy-groups:
  - name: Proxy
    type: select
    proxies:
      - Airport-A
      - Airport-B
      - Residential
rules:
  - DOMAIN-SUFFIX,example.cn,DIRECT
  - MATCH,Proxy
''';

  test('disabled chain leaves generated yaml byte-for-byte unchanged', () {
    expect(
      applyWindowsProxyChainYaml(source, const WindowsProxyChainSettings()),
      source,
    );
  });

  test('ordered nodes use Clash Verge dialer-proxy semantics', () {
    const settings = WindowsProxyChainSettings(
      enabled: true,
      nodes: ['Airport-A', 'Airport-B', 'Residential'],
      targetGroup: 'Proxy',
    );
    final parsed = loadYaml(applyWindowsProxyChainYaml(source, settings));
    final proxies = parsed['proxies'] as YamlList;
    final byName = <String, YamlMap>{
      for (final item in proxies.whereType<YamlMap>()) item['name'].toString(): item,
    };

    expect(byName['Airport-A']?['dialer-proxy'], isNull);
    expect(byName['Airport-B']?['dialer-proxy'], 'Airport-A');
    expect(byName['Residential']?['dialer-proxy'], 'Airport-B');
  });

  test('rules and proxy groups are not changed by the chain overlay', () {
    const settings = WindowsProxyChainSettings(
      enabled: true,
      nodes: ['Airport-A', 'Residential'],
      targetGroup: 'Proxy',
    );
    final before = normalize(loadYaml(source)) as Map<String, dynamic>;
    final after = normalize(
      loadYaml(applyWindowsProxyChainYaml(source, settings)),
    ) as Map<String, dynamic>;

    expect(after['rules'], before['rules']);
    expect(after['proxy-groups'], before['proxy-groups']);
    expect(after['mode'], before['mode']);
    expect(after.keys.toSet(), before.keys.toSet());
  });

  test('missing node fails visibly instead of modifying the subscription', () {
    const settings = WindowsProxyChainSettings(
      enabled: true,
      nodes: ['Airport-A', 'Deleted-Node'],
      targetGroup: 'Proxy',
    );
    expect(
      () => applyWindowsProxyChainYaml(source, settings),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('节点已不存在'),
        ),
      ),
    );
  });

  test('duplicate nodes are rejected', () {
    const settings = WindowsProxyChainSettings(
      enabled: true,
      nodes: ['Airport-A', 'Airport-A'],
      targetGroup: 'Proxy',
    );
    expect(
      () => applyWindowsProxyChainYaml(source, settings),
      throwsA(isA<StateError>()),
    );
  });

  test('subscription-authored dialer-proxy is never overwritten', () {
    const authored = '''
proxies:
  - name: Airport-A
    type: ss
    server: 127.0.0.1
    port: 10001
    cipher: aes-128-gcm
    password: a
  - name: Residential
    type: socks5
    server: 10.0.0.8
    port: 1080
    dialer-proxy: Existing-Upstream
proxy-groups:
  - name: Proxy
    type: select
    proxies: [Airport-A, Residential]
rules:
  - MATCH,Proxy
''';
    const settings = WindowsProxyChainSettings(
      enabled: true,
      nodes: ['Airport-A', 'Residential'],
      targetGroup: 'Proxy',
    );
    expect(
      () => applyWindowsProxyChainYaml(authored, settings),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('已自带 dialer-proxy'),
        ),
      ),
    );
  });

  test('settings persistence contains no subscription path or delete state', () {
    const settings = WindowsProxyChainSettings(
      enabled: true,
      nodes: ['Airport-A', 'Residential'],
      targetGroup: 'Proxy',
    );
    final json = settings.toJson();
    expect(json.keys.toSet(), {'enabled', 'nodes', 'targetGroup'});
    expect(WindowsProxyChainSettings.fromJson(json).nodes, settings.nodes);
    expect(
      WindowsProxyChainSettings.fromJson(json).targetGroup,
      settings.targetGroup,
    );
  });
}
