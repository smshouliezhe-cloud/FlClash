package cloud.smshouliezhe.privacychain.model

data class ResidentialProxy(
    val enabled: Boolean = false,
    val host: String = "",
    val port: Int = 0,
    val username: String = "",
    val password: String = "",
    val udp: Boolean = true,
) {
    val isComplete: Boolean
        get() = !enabled || (host.isNotBlank() && port in 1..65535)
}

data class LeakProtectionPolicy(
    val dnsHijack: Boolean = true,
    val strictRoute: Boolean = true,
    val blockDirectFallback: Boolean = true,
    val protectIpv6: Boolean = true,
    val blockUdpWhenLandingHasNoUdp: Boolean = true,
)

data class EnvironmentProfile(
    val timeZoneId: String = "",
    val languageTag: String = "",
    val regionCode: String = "",
)

data class PrivacyProfile(
    val name: String = "Default",
    val airportNode: String = "Auto",
    val residential: ResidentialProxy = ResidentialProxy(),
    val leakProtection: LeakProtectionPolicy = LeakProtectionPolicy(),
    val environment: EnvironmentProfile = EnvironmentProfile(),
)

enum class CheckLevel { PASS, WARNING, FAIL, UNKNOWN }

data class PrivacyCheck(
    val title: String,
    val detail: String,
    val level: CheckLevel,
)
