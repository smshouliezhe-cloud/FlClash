package cloud.smshouliezhe.privacychain

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import cloud.smshouliezhe.privacychain.model.CheckLevel
import cloud.smshouliezhe.privacychain.model.EnvironmentProfile
import cloud.smshouliezhe.privacychain.model.PrivacyCheck
import cloud.smshouliezhe.privacychain.model.PrivacyProfile
import cloud.smshouliezhe.privacychain.model.ResidentialProxy

class AppViewModel : ViewModel() {
    var selectedTab by mutableStateOf(AppTab.HOME)
        private set

    var profile by mutableStateOf(
        PrivacyProfile(
            name = "US Residential",
            airportNode = "香港 03",
            environment = EnvironmentProfile(
                timeZoneId = "America/Los_Angeles",
                languageTag = "en-US",
                regionCode = "US",
            ),
        ),
    )
        private set

    var isConnected by mutableStateOf(false)
        private set

    var checks by mutableStateOf(defaultChecks())
        private set

    fun selectTab(tab: AppTab) {
        selectedTab = tab
    }

    fun updateAirportNode(name: String) {
        profile = profile.copy(airportNode = name)
    }

    fun updateResidential(transform: (ResidentialProxy) -> ResidentialProxy) {
        profile = profile.copy(residential = transform(profile.residential))
    }

    fun updateEnvironment(transform: (EnvironmentProfile) -> EnvironmentProfile) {
        profile = profile.copy(environment = transform(profile.environment))
    }

    fun runPrivacyChecks() {
        val residential = profile.residential
        checks = listOf(
            PrivacyCheck(
                "DNS 接管",
                if (profile.leakProtection.dnsHijack) "已要求 TUN 劫持 53/UDP 与 53/TCP" else "未启用",
                if (profile.leakProtection.dnsHijack) CheckLevel.PASS else CheckLevel.FAIL,
            ),
            PrivacyCheck(
                "DIRECT 故障回退",
                if (profile.leakProtection.blockDirectFallback) "策略要求失败时阻断，不直连" else "允许回退直连",
                if (profile.leakProtection.blockDirectFallback) CheckLevel.PASS else CheckLevel.WARNING,
            ),
            PrivacyCheck(
                "住宅落地",
                when {
                    !residential.enabled -> "未启用住宅 SOCKS5"
                    residential.isComplete -> "参数完整，等待真实出口探测"
                    else -> "住宅 SOCKS5 参数不完整"
                },
                when {
                    !residential.enabled -> CheckLevel.WARNING
                    residential.isComplete -> CheckLevel.UNKNOWN
                    else -> CheckLevel.FAIL
                },
            ),
            PrivacyCheck("IPv6", "等待核心接入后执行 IPv6 出口泄漏检测", CheckLevel.UNKNOWN),
            PrivacyCheck("UDP / STUN", "等待核心接入后执行 UDP 出口一致性检测", CheckLevel.UNKNOWN),
            PrivacyCheck("系统时区", environmentDetail(), environmentLevel()),
        )
    }

    private fun environmentDetail(): String {
        val timeZone = profile.environment.timeZoneId
        return if (timeZone.isBlank()) "未配置环境时区" else "目标环境：$timeZone"
    }

    private fun environmentLevel(): CheckLevel =
        if (profile.environment.timeZoneId.isBlank()) CheckLevel.WARNING else CheckLevel.UNKNOWN

    private fun defaultChecks(): List<PrivacyCheck> = listOf(
        PrivacyCheck("DNS 泄漏", "尚未检测", CheckLevel.UNKNOWN),
        PrivacyCheck("IPv6 泄漏", "尚未检测", CheckLevel.UNKNOWN),
        PrivacyCheck("UDP / STUN", "尚未检测", CheckLevel.UNKNOWN),
        PrivacyCheck("系统环境一致性", "尚未检测", CheckLevel.UNKNOWN),
    )
}

enum class AppTab(val title: String) {
    HOME("首页"),
    NODES("节点"),
    CHAIN("链式代理"),
    PRIVACY("隐私"),
}
