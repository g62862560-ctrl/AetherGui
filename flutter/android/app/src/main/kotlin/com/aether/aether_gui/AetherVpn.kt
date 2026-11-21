package com.aether.aether_gui

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.net.VpnService
import android.os.ParcelFileDescriptor
import android.util.Log
import java.io.File
import java.util.concurrent.atomic.AtomicBoolean

// Full-device VPN: every app's IPv4 and IPv6 traffic enters the tun, hev-socks5-tunnel (tun2socks, built from
// src/main/jni) turns it into connections on aether's SOCKS5 port. DNS is answered inside the tun by
// hev's mapdns (fake IPs, the domain name goes to SOCKS), so it works even without SOCKS UDP support.
// ponytail: IPv4 only (aether runs with -4); IPv6 is left outside the tun, route ::/0 too if it leaks.
class AetherVpn : VpnService() {
    private var tun: ParcelFileDescriptor? = null

    @Synchronized
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            STOP, DISCONNECT -> {
                val stopped = stop("disconnected", reason = "requested")
                if (!stopped) Log.e(TAG, "native teardown failed during requested stop")
                stopSelfResult(startId)
                return START_NOT_STICKY
            }
            KEEP_ALIVE -> {
                if (tun == null && !tunnelOwned.get()) {
                    startForeground(NOTIFICATION_ID, notification(false))
                }
                return START_NOT_STICKY
            }
        }

        // Java ownership is valid only while both the descriptor and native worker live.
        // Process death used to be the only way to clear a stale half-owned session.
        val nativeRunning = nativeRunning()
        Log.i(TAG, "start requested: tun=${tun != null}, owned=${tunnelOwned.get()}, native=$nativeRunning")
        if (tun != null && tunnelOwned.get() && nativeRunning) {
            publishState("connected", owned = true)
            return START_NOT_STICKY
        }
        if (tun != null || tunnelOwned.get() || nativeRunning) {
            Log.w(TAG, "reconciling stale VPN state before start")
            val stopped = stop(null)
            if (!stopped) return failStart("stale tun2socks session could not be stopped")
        }
        publishState("starting", owned = false)
        startForeground(NOTIFICATION_ID, notification(true))
        val port = intent?.getIntExtra(EXTRA_PORT, DEFAULT_PORT) ?: DEFAULT_PORT
        if (port !in 1..65535) return failStart("Invalid SOCKS port")
        try {
            val t = Builder()
                .setSession("Aether VPN")
                .setMtu(MTU)
                .addAddress("198.18.0.1", 32)
                .addRoute("0.0.0.0", 0)
                .addAddress("fc00::1", 128)
                .addRoute("::", 0)
                .addDnsServer(DNS)
                .addDisallowedApplication(packageName)
                .establish() ?: return failStart("VPN permission was revoked before the tunnel was established")
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
                  cache-size: 10000
                misc:
                  log-level: warn
                """.trimIndent()
            )
            if (!TProxyStartService(conf.path, t.fd)) {
                return failStart("tun2socks failed to start")
            }
            tunnelOwned.set(true)
            publishState("connected", owned = true)
        } catch (e: Exception) {
            return failStart(e.message ?: e.javaClass.simpleName)
        }
        return START_NOT_STICKY
    }

    private fun notification(showDisconnect: Boolean): Notification {
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel(CHANNEL_ID, "VPN", NotificationManager.IMPORTANCE_LOW))
        val builder = Notification.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_launcher_foreground)
            .setContentTitle("Aether is running")
            .setContentIntent(PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT))
            .setOngoing(true)
        if (showDisconnect) {
            val stopIntent = Intent(this, AetherVpn::class.java).setAction(DISCONNECT)
            builder.addAction(Notification.Action.Builder(null, "Disconnect", PendingIntent.getService(
                this, 1, stopIntent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)).build())
        }
        return builder.build()
    }

    private fun failStart(message: String): Int {
        Log.e(TAG, message)
        stop(null)
        publishState("error", owned = false, error = message)
        stopSelf()
        return START_NOT_STICKY
    }

    @Synchronized
    override fun onRevoke() {
        stop(null)
        publishState("disconnected", owned = false, reason = "revoked")
        stopSelf()
        super.onRevoke()
    }

    @Synchronized
    override fun onDestroy() {
        val wasOwned = tunnelOwned.get()
        stop(null)
        if (wasOwned) publishState("disconnected", owned = false)
        super.onDestroy()
    }

    private fun stop(finalState: String?, reason: String? = null): Boolean {
        // Clear Java-side ownership before native teardown so concurrent queries
        // never report a tunnel whose close has already begun.
        val descriptor = tun
        tun = null
        val wasOwned = tunnelOwned.getAndSet(false)
        val wasRunning = descriptor != null || wasOwned
        if (wasRunning) publishState("stopping", owned = false)
        var nativeStopped = true
        try {
            if (nativeRunning()) nativeStopped = TProxyStopService()
            if (!nativeStopped) Log.w(TAG, "tun2socks reported stop failure")
        } catch (e: Exception) {
            nativeStopped = false
            Log.w(TAG, "tun2socks stop failed", e)
        } finally {
            if (descriptor != null) {
                try { descriptor.close() } catch (e: Exception) { Log.w(TAG, "tun close failed", e) }
            }
        }
        val stillRunning = nativeRunning()
        val stopped = nativeStopped && !stillRunning
        Log.i(TAG, "stop completed: wasOwned=$wasOwned, nativeStopped=$nativeStopped, nativeRunning=$stillRunning")
        if (finalState != null) publishState(
            finalState,
            owned = false,
            error = if (stopped) null else "tun2socks did not stop cleanly",
            reason = reason,
            stopSucceeded = stopped,
        )
        return stopped
    }

    private fun nativeRunning(): Boolean = try {
        TProxyIsRunning()
    } catch (e: Exception) {
        Log.w(TAG, "could not query tun2socks state", e)
        false
    }

    private fun publishState(
        state: String,
        owned: Boolean,
        error: String? = null,
        reason: String? = null,
        stopSucceeded: Boolean = true,
    ) {
        val intent = Intent(VPN_STATE_CHANGED).setPackage(packageName)
            .putExtra(EXTRA_STATE, state)
            .putExtra(EXTRA_OWNED, owned)
            .putExtra(EXTRA_STOP_SUCCEEDED, stopSucceeded)
        error?.let { intent.putExtra(EXTRA_ERROR, it) }
        reason?.let { intent.putExtra(EXTRA_REASON, it) }
        sendBroadcast(intent)
    }

    // Must match hev-jni.c exactly: JNI_OnLoad registers all four, one mismatch aborts the app.
    private external fun TProxyStartService(configPath: String, fd: Int): Boolean
    private external fun TProxyStopService(): Boolean
    @Suppress("unused") private external fun TProxyIsRunning(): Boolean
    @Suppress("unused") private external fun TProxyGetStats(): LongArray

    companion object {
        const val STOP = "stop"
        const val DISCONNECT = "com.aether.aether_gui.DISCONNECT"
        const val KEEP_ALIVE = "keepAlive"
        const val VPN_STATE_CHANGED = "com.aether.aether_gui.VPN_STATE_CHANGED"
        const val EXTRA_STATE = "state"
        const val EXTRA_OWNED = "owned"
        const val EXTRA_ERROR = "error"
        const val EXTRA_REASON = "reason"
        const val EXTRA_STOP_SUCCEEDED = "stopSucceeded"
        const val EXTRA_PORT = "port"
        const val MTU = 8500
        const val DNS = "198.18.0.2"
        private const val DEFAULT_PORT = 1818
        private const val CHANNEL_ID = "vpn"
        private const val NOTIFICATION_ID = 1
        private const val TAG = "AetherVpn"
        private val tunnelOwned = AtomicBoolean(false)

        fun isTunnelOwned(): Boolean = tunnelOwned.get()

        init {
            System.loadLibrary("hev-socks5-tunnel")
        }
    }
}
