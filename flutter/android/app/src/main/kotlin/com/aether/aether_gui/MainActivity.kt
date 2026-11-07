package com.aether.aether_gui

import android.content.Intent
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.net.VpnService
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pending: Pair<Int, MethodChannel.Result>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "aether").setMethodCallHandler { call, result ->
            when (call.method) {
                "dirs" -> result.success(listOf(applicationInfo.nativeLibraryDir, filesDir.path))
                "appVersion" -> result.success(packageManager.getPackageInfo(packageName, 0).versionName)
                "vpnActive" -> {
                    try {
                        val cm = getSystemService(CONNECTIVITY_SERVICE) as ConnectivityManager
                        val network = cm.activeNetwork
                        val caps = network?.let { cm.getNetworkCapabilities(it) }
                        result.success(caps?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) == true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "vpnSettings" -> {
                    startActivity(Intent(Settings.ACTION_VPN_SETTINGS))
                    result.success(null)
                }
                "openUrl" -> {
                    startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(call.arguments as String)))
                    result.success(null)
                }
                "vpnStart" -> {
                    val port = call.arguments as Int
                    val consent = VpnService.prepare(this)
                    if (consent == null) result.success(startVpn(port))
                    else {
                        pending?.second?.success(false)
                        pending = port to result
                        startActivityForResult(consent, VPN_CONSENT)
                    }
                }
                "keepAlive" -> {
                    startService(Intent(this, AetherVpn::class.java).setAction(AetherVpn.KEEP_ALIVE))
                    result.success(null)
                }
                "vpnStop" -> {
                    startService(Intent(this, AetherVpn::class.java).setAction(AetherVpn.STOP))
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun startVpn(port: Int): Boolean {
        startService(Intent(this, AetherVpn::class.java).putExtra("port", port))
        return true
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != VPN_CONSENT) return
        val (port, result) = pending ?: return
        pending = null
        result.success(resultCode == RESULT_OK && startVpn(port))
    }

    companion object {
        const val VPN_CONSENT = 1
    }
}
