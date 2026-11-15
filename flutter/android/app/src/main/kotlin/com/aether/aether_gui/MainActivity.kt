package com.aether.aether_gui

import android.content.ComponentName
import android.content.Intent
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.net.VpnService
import android.os.Build
import android.os.PowerManager
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
                "deviceInfo" -> result.success(
                    listOf(Build.MANUFACTURER, Build.BRAND, Build.VERSION.SDK_INT.toString(), Build.VERSION.RELEASE)
                )
                "batteryIgnored" -> result.success(
                    (getSystemService(POWER_SERVICE) as PowerManager).isIgnoringBatteryOptimizations(packageName)
                )
                "openSetting" -> result.success(openSetting(call.arguments as String))
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

    // Opens a system screen; false when this device has no such screen (the caller falls back).
    private fun openSetting(kind: String): Boolean {
        val intents = when (kind) {
            "battery" -> listOf(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
            "saver" -> listOf(Intent(Settings.ACTION_BATTERY_SAVER_SETTINGS))
            "app" -> listOf(
                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName")),
            )
            // OEM screens are unofficial and move between versions, so try each known one.
            "oem" -> OEM_SCREENS.map { (pkg, cls) -> Intent().setComponent(ComponentName(pkg, cls)) }
            else -> emptyList()
        }
        for (intent in intents) {
            try {
                startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                return true
            } catch (_: Exception) {
            }
        }
        return false
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
        private val OEM_SCREENS = listOf(
            "com.miui.securitycenter" to "com.miui.permcenter.autostart.AutoStartManagementActivity",
            "com.huawei.systemmanager" to "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity",
            "com.huawei.systemmanager" to "com.huawei.systemmanager.optimize.process.ProtectActivity",
            "com.coloros.safecenter" to "com.coloros.safecenter.permission.startup.StartupAppListActivity",
            "com.coloros.safecenter" to "com.coloros.safecenter.startupapp.StartupAppListActivity",
            "com.oppo.safe" to "com.oppo.safe.permission.startup.StartupAppListActivity",
            "com.vivo.permissionmanager" to "com.vivo.permissionmanager.activity.BgStartUpManagerActivity",
            "com.iqoo.secure" to "com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity",
            "com.samsung.android.lool" to "com.samsung.android.sm.battery.ui.BatteryActivity",
            "com.oneplus.security" to "com.oneplus.security.chainlaunch.view.ChainLaunchAppListActivity",
        )
    }
}
