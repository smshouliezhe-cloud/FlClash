package cloud.smshouliezhe.privacychain.vpn

import android.content.Intent
import android.net.VpnService
import android.os.IBinder

/**
 * Android VPN boundary for PrivacyChain.
 *
 * The service intentionally does not establish a tunnel yet. The next core
 * integration step will attach Mihomo's TUN file descriptor here. Keeping the
 * boundary explicit prevents the prototype from silently black-holing traffic.
 */
class PrivacyVpnService : VpnService() {
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // TODO(core): hand the established TUN fd to the Mihomo core bridge.
        stopSelf(startId)
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = super.onBind(intent)
}
