package com.capsuleutkarsh.music_player

import android.Manifest
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.content.pm.PackageManager
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/// AudioServiceActivity shares its Flutter engine with the media service, so music plays on in the
/// background. The "lumen/android" channel asks for the music permission and tells Dart where the
/// sound goes (speaker, wired, USB or Bluetooth) and at what rate the device runs.
class MainActivity : AudioServiceActivity() {
    private var channel: MethodChannel? = null
    private var asked: MethodChannel.Result? = null
    private val audio by lazy { getSystemService(Context.AUDIO_SERVICE) as AudioManager }
    private val devices = object : AudioDeviceCallback() {
        override fun onAudioDevicesAdded(added: Array<out AudioDeviceInfo>) { channel?.invokeMethod("route", route()) }
        override fun onAudioDevicesRemoved(removed: Array<out AudioDeviceInfo>) { channel?.invokeMethod("route", route()) }
    }

    private val musicPermission =
        if (Build.VERSION.SDK_INT >= 33) Manifest.permission.READ_MEDIA_AUDIO else Manifest.permission.READ_EXTERNAL_STORAGE

    private fun hasMusic() = checkSelfPermission(musicPermission) == PackageManager.PERMISSION_GRANTED

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lumen/android").apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "hasMusic" -> result.success(hasMusic())
                    "askMusic" -> {
                        val wanted = mutableListOf(musicPermission)
                        if (Build.VERSION.SDK_INT >= 33) wanted += Manifest.permission.POST_NOTIFICATIONS
                        asked = result
                        requestPermissions(wanted.toTypedArray(), 1)
                    }
                    "route" -> result.success(route())
                    "version" -> result.success(packageManager.getPackageInfo(packageName, 0).versionName)
                    "open" -> {
                        startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(call.arguments as String)))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
        audio.registerAudioDeviceCallback(devices, null)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        audio.unregisterAudioDeviceCallback(devices)
        channel?.setMethodCallHandler(null)
        channel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        asked?.success(hasMusic())
        asked = null
    }

    /// Where media plays, in Android's own order for music: Bluetooth, then wired, then USB, then the speaker.
    /// ponytail: a guess from the connected outputs; Android 13's getAudioDevicesForAttributes knows for sure.
    private fun route(): Map<String, Any> {
        val outs = audio.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
        fun of(vararg types: Int) = outs.firstOrNull { it.type in types }
        val (kind, d) = listOf(
            "bluetooth" to of(AudioDeviceInfo.TYPE_BLUETOOTH_A2DP),
            "wired" to of(AudioDeviceInfo.TYPE_WIRED_HEADPHONES, AudioDeviceInfo.TYPE_WIRED_HEADSET),
            "usb" to of(AudioDeviceInfo.TYPE_USB_HEADSET, AudioDeviceInfo.TYPE_USB_DEVICE),
        ).firstOrNull { it.second != null } ?: ("speaker" to of(AudioDeviceInfo.TYPE_BUILTIN_SPEAKER))
        val mixer = audio.getProperty(AudioManager.PROPERTY_OUTPUT_SAMPLE_RATE)?.toIntOrNull() ?: 0
        return mapOf(
            "kind" to kind,
            "product" to (d?.productName?.toString() ?: ""),
            "rates" to (d?.sampleRates?.toList() ?: emptyList<Int>()),
            "mixerRate" to mixer,
            "sdk" to Build.VERSION.SDK_INT,
        )
    }
}
