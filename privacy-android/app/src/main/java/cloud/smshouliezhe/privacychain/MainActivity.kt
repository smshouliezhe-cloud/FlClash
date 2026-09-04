package cloud.smshouliezhe.privacychain

import android.content.Intent
import android.net.VpnService
import android.os.Bundle
import android.provider.Settings
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.AccountTree
import androidx.compose.material.icons.outlined.Home
import androidx.compose.material.icons.outlined.Hub
import androidx.compose.material.icons.outlined.Security
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import cloud.smshouliezhe.privacychain.model.CheckLevel
import cloud.smshouliezhe.privacychain.model.PrivacyCheck

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            MaterialTheme {
                PrivacyChainApp()
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun PrivacyChainApp(vm: AppViewModel = viewModel()) {
    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Column {
                        Text("PrivacyChain")
                        Text("网络与环境隐私", style = MaterialTheme.typography.labelSmall)
                    }
                },
            )
        },
        bottomBar = {
            NavigationBar {
                AppTab.entries.forEach { tab ->
                    NavigationBarItem(
                        selected = vm.selectedTab == tab,
                        onClick = { vm.selectTab(tab) },
                        icon = { androidx.compose.material3.Icon(tab.icon(), contentDescription = tab.title) },
                        label = { Text(tab.title) },
                    )
                }
            }
        },
    ) { padding ->
        when (vm.selectedTab) {
            AppTab.HOME -> HomeScreen(vm, Modifier.padding(padding))
            AppTab.NODES -> NodesScreen(vm, Modifier.padding(padding))
            AppTab.CHAIN -> ChainScreen(vm, Modifier.padding(padding))
            AppTab.PRIVACY -> PrivacyScreen(vm, Modifier.padding(padding))
        }
    }
}

@Composable
private fun HomeScreen(vm: AppViewModel, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val vpnPermissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.StartActivityForResult(),
    ) { }

    Page(modifier) {
        StatusCard(
            title = if (vm.isConnected) "已连接" else "未连接",
            subtitle = "第一版先完成安全边界和配置生成，Mihomo TUN 正在接入",
        )

        SectionTitle("当前链路")
        Card(Modifier.fillMaxWidth()) {
            Column(
                modifier = Modifier.padding(20.dp).fillMaxWidth(),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Text(vm.profile.airportNode, fontWeight = FontWeight.SemiBold)
                Text("↓", style = MaterialTheme.typography.headlineMedium)
                Text(
                    if (vm.profile.residential.enabled) "住宅 SOCKS5" else "直接由机场节点出口",
                    fontWeight = FontWeight.SemiBold,
                )
                Text("↓", style = MaterialTheme.typography.headlineMedium)
                Text("Internet")
            }
        }

        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Button(
                modifier = Modifier.weight(1f),
                onClick = {
                    val intent = VpnService.prepare(context)
                    if (intent != null) vpnPermissionLauncher.launch(intent)
                },
            ) { Text("请求 VPN 授权") }
            OutlinedButton(
                modifier = Modifier.weight(1f),
                onClick = {
                    vm.runPrivacyChecks()
                    vm.selectTab(AppTab.PRIVACY)
                },
            ) { Text("隐私体检") }
        }

        SectionTitle("默认保护")
        Text("DNS 劫持 · Strict Route · 禁止故障 DIRECT 回退 · IPv6/UDP 泄漏检查")
    }
}

@Composable
private fun NodesScreen(vm: AppViewModel, modifier: Modifier = Modifier) {
    Page(modifier) {
        SectionTitle("订阅与机场节点")
        Text("这一页下一步接订阅解析和 Mihomo provider。当前先保留最小可操作原型。")
        listOf("香港 03", "日本 01", "新加坡 02", "美国 05").forEach { node ->
            OutlinedButton(
                modifier = Modifier.fillMaxWidth(),
                onClick = { vm.updateAirportNode(node) },
            ) {
                Text(if (vm.profile.airportNode == node) "✓ $node" else node)
            }
        }
    }
}

@Composable
private fun ChainScreen(vm: AppViewModel, modifier: Modifier = Modifier) {
    val proxy = vm.profile.residential
    Page(modifier) {
        SectionTitle("住宅落地代理")
        Text("固定模型：机场节点 → 住宅 SOCKS5 → Internet。切换机场节点时住宅出口保持不变。")

        SettingSwitch(
            title = "启用住宅落地",
            detail = "不修改订阅源文件，只在最终运行配置上生成 wrapper",
            checked = proxy.enabled,
            onCheckedChange = { value -> vm.updateResidential { it.copy(enabled = value) } },
        )

        OutlinedTextField(
            value = proxy.host,
            onValueChange = { value -> vm.updateResidential { it.copy(host = value.trim()) } },
            modifier = Modifier.fillMaxWidth(),
            label = { Text("SOCKS5 地址") },
            enabled = proxy.enabled,
            singleLine = true,
        )
        OutlinedTextField(
            value = if (proxy.port == 0) "" else proxy.port.toString(),
            onValueChange = { value -> vm.updateResidential { it.copy(port = value.filter(Char::isDigit).toIntOrNull() ?: 0) } },
            modifier = Modifier.fillMaxWidth(),
            label = { Text("端口") },
            enabled = proxy.enabled,
            singleLine = true,
        )
        OutlinedTextField(
            value = proxy.username,
            onValueChange = { value -> vm.updateResidential { it.copy(username = value) } },
            modifier = Modifier.fillMaxWidth(),
            label = { Text("用户名（可选）") },
            enabled = proxy.enabled,
            singleLine = true,
        )
        OutlinedTextField(
            value = proxy.password,
            onValueChange = { value -> vm.updateResidential { it.copy(password = value) } },
            modifier = Modifier.fillMaxWidth(),
            label = { Text("密码（可选）") },
            enabled = proxy.enabled,
            visualTransformation = PasswordVisualTransformation(),
            singleLine = true,
        )
        SettingSwitch(
            title = "SOCKS5 UDP",
            detail = "关闭时后续策略会阻断不能安全落地的 UDP，而不是自动 DIRECT",
            checked = proxy.udp,
            onCheckedChange = { value -> vm.updateResidential { it.copy(udp = value) } },
            enabled = proxy.enabled,
        )

        StatusCard(
            title = if (proxy.isComplete) "配置状态正常" else "配置不完整",
            subtitle = if (proxy.enabled) "保存层和核心接入将在下一阶段完成" else "当前使用普通机场出口",
        )
    }
}

@Composable
private fun PrivacyScreen(vm: AppViewModel, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val environment = vm.profile.environment

    Page(modifier) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            SectionTitle("泄漏保护")
            Button(onClick = vm::runPrivacyChecks) { Text("重新检测") }
        }

        vm.checks.forEach { check -> PrivacyCheckCard(check) }

        HorizontalDivider()
        SectionTitle("环境一致性")
        Text("环境信息属于本机暴露面，不走 VPN。第一阶段先检测并管理目标配置；系统级自动同步能力后续按权限模式接入。")

        OutlinedTextField(
            value = environment.timeZoneId,
            onValueChange = { value -> vm.updateEnvironment { it.copy(timeZoneId = value) } },
            modifier = Modifier.fillMaxWidth(),
            label = { Text("目标时区，例如 America/Los_Angeles") },
            singleLine = true,
        )
        OutlinedTextField(
            value = environment.languageTag,
            onValueChange = { value -> vm.updateEnvironment { it.copy(languageTag = value) } },
            modifier = Modifier.fillMaxWidth(),
            label = { Text("目标语言，例如 en-US") },
            singleLine = true,
        )

        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            OutlinedButton(
                modifier = Modifier.weight(1f),
                onClick = { context.startActivity(Intent(Settings.ACTION_DATE_SETTINGS)) },
            ) { Text("系统时区") }
            OutlinedButton(
                modifier = Modifier.weight(1f),
                onClick = { context.startActivity(Intent(Settings.ACTION_LOCALE_SETTINGS)) },
            ) { Text("系统语言") }
        }

        StatusCard(
            title = "安全原则",
            subtitle = "无法确认代理链完整时宁可阻断，也不静默回落到真实网络。",
        )
    }
}

@Composable
private fun Page(modifier: Modifier, content: @Composable Column.() -> Unit) {
    Column(
        modifier = modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
        content = content,
    )
}

@Composable
private fun SectionTitle(text: String) {
    Text(text, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
}

@Composable
private fun StatusCard(title: String, subtitle: String) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainer),
    ) {
        Column(Modifier.padding(16.dp)) {
            Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
            Spacer(Modifier.height(4.dp))
            Text(subtitle, style = MaterialTheme.typography.bodyMedium)
        }
    }
}

@Composable
private fun SettingSwitch(
    title: String,
    detail: String,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
    enabled: Boolean = true,
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f)) {
            Text(title, fontWeight = FontWeight.SemiBold)
            Text(detail, style = MaterialTheme.typography.bodySmall)
        }
        Switch(checked = checked, onCheckedChange = onCheckedChange, enabled = enabled)
    }
}

@Composable
private fun PrivacyCheckCard(check: PrivacyCheck) {
    val marker = when (check.level) {
        CheckLevel.PASS -> "✓"
        CheckLevel.WARNING -> "⚠"
        CheckLevel.FAIL -> "✕"
        CheckLevel.UNKNOWN -> "…"
    }
    Card(Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier.padding(16.dp).fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(marker, style = MaterialTheme.typography.titleLarge)
            Column(Modifier.padding(start = 12.dp)) {
                Text(check.title, fontWeight = FontWeight.SemiBold)
                Text(check.detail, style = MaterialTheme.typography.bodySmall)
            }
        }
    }
}

private fun AppTab.icon(): ImageVector = when (this) {
    AppTab.HOME -> Icons.Outlined.Home
    AppTab.NODES -> Icons.Outlined.Hub
    AppTab.CHAIN -> Icons.Outlined.AccountTree
    AppTab.PRIVACY -> Icons.Outlined.Security
}
