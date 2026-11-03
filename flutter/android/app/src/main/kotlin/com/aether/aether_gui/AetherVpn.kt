package com.aether.aether_gui

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.net.VpnService
import android.os.ParcelFileDescriptor
import java.io.File

// Full-device VPN: every app's IPv4 and IPv6 traffic enters the tun, hev-socks5-tunnel (tun2socks, built from
// src/main/jni) turns it into connections on aether's SOCKS5 port. DNS is answered inside the tun by
// hev's mapdns (fake IPs, the domain name goes to SOCKS), so it works even without SOCKS UDP support.
// ponytail: IPv4 only (aether runs with -4); IPv6 is left outside the tun, route ::/0 too if it leaks.
class AetherVpn : VpnService() {
    private var tun: ParcelFileDescriptor? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        stop()
        if (intent?.action == STOP) {
            stopSelf()
            return START_NOT_STICKY
        }
        // Foreground keeps the whole process (aether child + Dart monitor) alive when the app is backgrounded or the screen locks.
        getSystemService(NotificationManager::class.java)
            .createNotificationChannel(NotificationChannel("vpn", "VPN", NotificationManager.IMPORTANCE_LOW))
        startForeground(
            1,
            Notification.Builder(this, "vpn")
                .setSmallIcon(R.drawable.ic_launcher_foreground)
                .setContentTitle("Aether is running")
                .setContentIntent(PendingIntent.getActivity(this, 0,
                    Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE))
                .setOngoing(true)
                .build(),
        )
        if (intent?.action == KEEP_ALIVE) return START_NOT_STICKY // proxy mode: no tun, just stay alive
        val port = intent?.getIntExtra("port", 1818) ?: 1818
        val t = Builder()
            .setSession("Aether VPN")
            .setMtu(MTU)
            .addAddress("198.18.0.1", 32)
            .addRoute("0.0.0.0", 0)
            // IPv6 must enter the tun too, or it bypasses the VPN on IPv6 networks.
            .addAddress("fc00::1", 128)
            .addRoute("::", 0)
            .addDnsServer(DNS)
            .addDisallowedApplication(packageName) // aether itself must reach the internet directly
            .establish() ?: return START_NOT_STICKY // consent revoked meanwhile
        tun = t
        val conf = File(cacheDir, "tun.yml")
        conf.writeText(
            """
            tunnel:
              mtu: $MTU
              ipv4: 198.18.0.1
              ipv6: 'fc00::1'
            socks5:
              address: 127.0.0.1
              port: $port
              udp: 'udp'
            mapdns:
              address: $DNS
              port: 53
              network: 100.64.0.0
              netmask: 255.192.0.0
              cache-size: 10000 # required: 0/absent silently disables mapdns
            misc:
              log-level: warn
            """.trimIndent()
        )
        TProxyStartService(conf.path, t.fd)
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        stop() // also reached via onRevoke (another VPN took over), whose default calls stopSelf
        super.onDestroy()
    }

    private fun stop() {
        if (tun == null) return
        TProxyStopService()
        tun?.close()
        tun = null
    }

    // Must match hev-jni.c exactly: JNI_OnLoad registers all four, one mismatch aborts the app.
    private external fun TProxyStartService(configPath: String, fd: Int): Boolean
    private external fun TProxyStopService(): Boolean
    @Suppress("unused") private external fun TProxyIsRunning(): Boolean
    @Suppress("unused") private external fun TProxyGetStats(): LongArray

    companion object {
        const val STOP = "stop"
        const val KEEP_ALIVE = "keepAlive"
        const val MTU = 8500
        const val DNS = "198.18.0.2"

        init {
            System.loadLibrary("hev-socks5-tunnel")
        }
    }
}
