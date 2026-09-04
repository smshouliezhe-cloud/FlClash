package cloud.smshouliezhe.privacychain.core

import cloud.smshouliezhe.privacychain.model.PrivacyProfile

/**
 * Builds the privacy-sensitive overlay that will eventually be merged into the
 * subscription generated runtime config. This deliberately does not persist or
 * rewrite the user's source subscription.
 */
object MihomoRuntimeConfigBuilder {
    fun buildResidentialProxyYaml(
        visibleNodeName: String,
        hiddenAirportNodeName: String,
        profile: PrivacyProfile,
    ): String {
        val residential = profile.residential
        require(residential.enabled) { "Residential landing is disabled" }
        require(residential.isComplete) { "Residential SOCKS5 settings are incomplete" }

        return buildString {
            appendLine("- name: ${yamlString(visibleNodeName)}")
            appendLine("  type: socks5")
            appendLine("  server: ${yamlString(residential.host)}")
            appendLine("  port: ${residential.port}")
            appendLine("  udp: ${residential.udp}")
            appendLine("  dialer-proxy: ${yamlString(hiddenAirportNodeName)}")
            if (residential.username.isNotBlank()) {
                appendLine("  username: ${yamlString(residential.username)}")
            }
            if (residential.password.isNotEmpty()) {
                appendLine("  password: ${yamlString(residential.password)}")
            }
        }.trimEnd()
    }

    fun buildTunProtectionYaml(profile: PrivacyProfile): String {
        val policy = profile.leakProtection
        return buildString {
            appendLine("tun:")
            appendLine("  enable: true")
            appendLine("  stack: mixed")
            appendLine("  auto-route: true")
            appendLine("  auto-detect-interface: true")
            appendLine("  strict-route: ${policy.strictRoute}")
            if (policy.dnsHijack) {
                appendLine("  dns-hijack:")
                appendLine("    - any:53")
                appendLine("    - tcp://any:53")
            }
            appendLine("ipv6: ${policy.protectIpv6}")
        }.trimEnd()
    }

    private fun yamlString(value: String): String =
        "\"${value.replace("\\", "\\\\").replace("\"", "\\\"")}\""
}
