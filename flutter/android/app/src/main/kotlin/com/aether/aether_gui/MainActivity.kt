package com.aether.aether_gui

import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
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
    private var channel: MethodChannel? = null
    private var receiverRegistered = false
    private val vpnReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            when (intent?.action) {
                AetherVpn.VPN_STATE_CHANGED -> channel?.invokeMethod("vpnState", hashMapOf(
                    "state" to intent.getStringExtra(AetherVpn.EXTRA_STATE),
                    "owned" to intent.getBooleanExtra(AetherVpn.EXTRA_OWNED, false),
                    "error" to intent.getStringExtra(AetherVpn.EXTRA_ERROR),
                    "reason" to intent.getStringExtra(AetherVpn.EXTRA_REASON),
                ))
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "aether").also { methodChannel ->
            methodChannel.setMethodCallHandler { call, result ->
                when (call.method) {
                "dirs" -> result.success(listOf(applicationInfo.nativeLibraryDir, filesDir.path))
                "appVersion" -> result.success(packageManager.getPackageInfo(packageName, 0).versionName)
                "vpnActive" -> result.success(AetherVpn.isTunnelOwned())
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
                    val port = call.arguments as? Int
                    if (port == null || port !in 1..65535) {
                        result.error("invalid_port", "SOCKS port must be between 1 and 65535", null)
                    } else if (AetherVpn.isTunnelOwned()) {
                        result.success(true)
                    } else {
                        val consent = VpnService.prepare(this)
                        if (consent == null) result.success(startVpn(port))
                        else {
                            pending?.second?.success(false)
                            pending = port to result
                            try {
                                startActivityForResult(consent, VPN_CONSENT)
                            } catch (e: Exception) {
                                pending = null
                                result.error("vpn_consent", e.message ?: "Unable to request VPN consent", null)
                            }
                        }
                    }
                }
                "keepAlive" -> result.success(dispatchService(Intent(this, AetherVpn::class.java)
                    .setAction(AetherVpn.KEEP_ALIVE)))
                "vpnStop" -> result.success(dispatchService(Intent(this, AetherVpn::class.java)
                    .setAction(AetherVpn.STOP)))
                else -> result.notImplemented()
            }
            }
        }
        if (!receiverRegistered) {
            val filter = IntentFilter(AetherVpn.VPN_STATE_CHANGED)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(vpnReceiver, filter, RECEIVER_NOT_EXPORTED)
            } else {
                @Suppress("UnspecifiedRegisterReceiverFlag")
                registerReceiver(vpnReceiver, filter)
            }
            receiverRegistered = true
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        if (receiverRegistered) {
            unregisterReceiver(vpnReceiver)
            receiverRegistered = false
        }
        pending?.second?.success(false)
        pending = null
        channel?.setMethodCallHandler(null)
        channel = null
        super.cleanUpFlutterEngine(flutterEngine)
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

    private fun startVpn(port: Int): Boolean = dispatchService(
        Intent(this, AetherVpn::class.java).putExtra(AetherVpn.EXTRA_PORT, port),
    )

    private fun dispatchService(intent: Intent): Boolean = try {
        startService(intent) != null
    } catch (_: Exception) {
        false
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
