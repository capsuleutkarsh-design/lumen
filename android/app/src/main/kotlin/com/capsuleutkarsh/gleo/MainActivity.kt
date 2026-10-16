package com.capsuleutkarsh.gleo

import android.Manifest
import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Environment
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import android.content.pm.PackageManager
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.view.WindowManager
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/// AudioServiceActivity shares its Flutter engine with the media service, so music plays on in the
/// background. The "gleo/android" channel asks for the music permission and tells Dart where the
/// sound goes (speaker, wired, USB or Bluetooth) and at what rate the device runs. It also picks a music
/// folder on any storage (the phone or an SD card), saves a file where the user chooses, and copies the
/// .lrc and .cue files Android 13+ hides from the music permission (see mirror).
/// When the screen goes off with Gleo in front and music playing, Gleo's lock-screen view shows over the
/// lock screen when the phone wakes (no background start, no full-screen intent).
class MainActivity : AudioServiceActivity() {
    private var channel: MethodChannel? = null
    private var asked: MethodChannel.Result? = null
    private var picked: MethodChannel.Result? = null
    private var saved: MethodChannel.Result? = null
    private var saveText = ""
    private val audio by lazy { getSystemService(Context.AUDIO_SERVICE) as AudioManager }
    private val keyguard by lazy { getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager }
    private var locked = false // the lock-screen view is up
    private var resumed = false
    private var notifyAsked = false
    private val devices = object : AudioDeviceCallback() {
        override fun onAudioDevicesAdded(added: Array<out AudioDeviceInfo>) { channel?.invokeMethod("route", route()) }
        override fun onAudioDevicesRemoved(removed: Array<out AudioDeviceInfo>) { channel?.invokeMethod("route", route()) }
    }

    private val musicPermission =
        if (Build.VERSION.SDK_INT >= 33) Manifest.permission.READ_MEDIA_AUDIO else Manifest.permission.READ_EXTERNAL_STORAGE

    private fun has(p: String) = checkSelfPermission(p) == PackageManager.PERMISSION_GRANTED
    private fun hasMusic() = has(musicPermission)

    /// After asking: "granted" ("photos" when Android 13+ should ask for images next), "denied", or "blocked"
    /// (Android no longer shows the dialog: only Settings can give it).
    private fun musicState() = when {
        hasMusic() -> if (Build.VERSION.SDK_INT >= 33 && !has(Manifest.permission.READ_MEDIA_IMAGES)) "photos" else "granted"
        shouldShowRequestPermissionRationale(musicPermission) -> "denied"
        else -> "blocked"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "gleo/android").apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "hasMusic" -> result.success(hasMusic())
                    "askMusic" -> {
                        asked = result
                        requestPermissions(arrayOf(musicPermission), MUSIC)
                    }
                    // Android 13+: images, for folder.jpg / cover.jpg (refusing them only loses those covers).
                    "askPhotos" -> {
                        asked = result
                        requestPermissions(arrayOf(Manifest.permission.READ_MEDIA_IMAGES), PHOTOS)
                    }
                    // Android 13+: the media notification, asked the first time something plays with Gleo in front.
                    "askNotifications" -> {
                        if (Build.VERSION.SDK_INT >= 33 && resumed && !notifyAsked && !has(Manifest.permission.POST_NOTIFICATIONS)) {
                            notifyAsked = true
                            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), NOTIFY)
                        }
                        result.success(null)
                    }
                    "openSettings" -> {
                        startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", packageName, null)))
                        result.success(null)
                    }
                    "lockAllowed" -> {
                        lockAllowed = call.arguments as Boolean
                        result.success(null)
                    }
                    // "Open Gleo" on the lock-screen view: Android asks for the PIN / fingerprint, then the full app.
                    "unlock" -> {
                        keyguard.requestDismissKeyguard(this@MainActivity, object : KeyguardManager.KeyguardDismissCallback() {
                            override fun onDismissSucceeded() = setLocked(false)
                        })
                        result.success(null)
                    }
                    "keepOn" -> {
                        keepOn = call.arguments as Boolean
                        keepScreenOn()
                        result.success(null)
                    }
                    "route" -> result.success(route())
                    "pickFolder" -> {
                        picked = result
                        // Opens at the Music folder (Android 8+ honours the hint; it may still show the last place).
                        val music = DocumentsContract.buildDocumentUri("com.android.externalstorage.documents", "primary:Music")
                        startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).putExtra(DocumentsContract.EXTRA_INITIAL_URI, music), PICK)
                    }
                    "save" -> {
                        val name = call.argument<String>("name")!!
                        saveText = call.argument<String>("text")!!
                        saved = result
                        val mime = MimeTypeMap.getSingleton().getMimeTypeFromExtension(name.substringAfterLast('.')) ?: "application/octet-stream"
                        startActivityForResult(
                            Intent(Intent.ACTION_CREATE_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE).setType(mime).putExtra(Intent.EXTRA_TITLE, name),
                            SAVE,
                        )
                    }
                    "mirror" -> {
                        val dest = call.argument<String>("dest")!!
                        val folders = call.argument<List<String>>("folders")!!
                        Thread {
                            val n = runCatching { mirror(dest, folders) }.getOrDefault(0)
                            runOnUiThread { result.success(n) }
                        }.start()
                    }
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
        // Kept after this activity closes: the widget follows the music playing on in the background.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "gleo/widget").setMethodCallHandler { call, result ->
            GleoWidget.update(applicationContext, call.arguments as Map<*, *>)
            result.success(null)
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        audio.unregisterAudioDeviceCallback(devices)
        channel?.setMethodCallHandler(null)
        channel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == NOTIFY) return
        asked?.success(if (requestCode == MUSIC) musicState() else null)
        asked = null
    }

    override fun onResume() {
        super.onResume()
        resumed = true
        keepScreenOn()
        if (locked && !keyguard.isKeyguardLocked) setLocked(false) // unlocked some other way, or no lock screen
    }

    override fun onPause() {
        super.onPause()
        resumed = false
        // The screen went off with Gleo in front: show the lock-screen view when it wakes, while music plays.
        if (!(getSystemService(Context.POWER_SERVICE) as PowerManager).isInteractive) setLocked(lockAllowed)
    }

    private fun keepScreenOn() =
        if (keepOn) window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        else window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

    private fun setLocked(on: Boolean) {
        if (on == locked) return
        locked = on
        channel?.invokeMethod("locked", on) // Dart swaps to the lock-screen view before this window can show
        if (Build.VERSION.SDK_INT >= 27) setShowWhenLocked(on)
        else if (on) window.addFlags(WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED)
        else window.clearFlags(WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        val uri = data?.data.takeIf { resultCode == RESULT_OK }
        when (requestCode) {
            PICK -> picked?.let { r ->
                picked = null
                // Kept: Android 13+ lets Gleo read the folder's .lrc and .cue files only through this access.
                if (uri != null) runCatching { contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION) }
                if (uri == null) r.success(null) else folderPath(uri)?.let { r.success(it) } ?: r.error("place", "not a storage folder", null)
            }
            SAVE -> saved?.let { r ->
                saved = null
                if (uri == null) return r.success(null)
                runCatching {
                    contentResolver.openOutputStream(uri, "wt")!!.use { it.write(saveText.toByteArray()) }
                    contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { if (it.moveToFirst()) it.getString(0) else null } ?: ""
                }.fold({ r.success(it) }, { r.error("save", it.message, null) })
            }
        }
    }

    /// The plain path of a folder picked in Android's folder picker: "primary:Music/Rock" is the phone's own
    /// storage, "1A2B-3C4D:Music" an SD card or USB stick (mounted at /storage/1A2B-3C4D). Other places
    /// (Downloads shortcuts, cloud apps) have no path: null.
    private fun folderPath(tree: Uri): String? {
        if (tree.authority != "com.android.externalstorage.documents") return null
        val (volume, rel) = DocumentsContract.getTreeDocumentId(tree).split(":", limit = 2).let { it[0] to it.getOrElse(1) { "" } }
        val root = if (volume == "primary") Environment.getExternalStorageDirectory().path else "/storage/$volume"
        return if (rel.isEmpty()) root else "$root/$rel"
    }

    /// Android 13+ shows Gleo only the music (and image) files: .lrc lyrics and .cue sheets stay hidden.
    /// For each of [folders] inside a folder picked in the folder picker (whose access Android keeps),
    /// copies its .lrc and .cue files to [dest] + their own path, where the lyrics and the scanner look,
    /// and removes copies whose file is gone. Returns how many copies changed.
    /// ponytail: one folder listing per song folder on every rescan; a change journal if that gets slow.
    private fun mirror(dest: String, folders: List<String>): Int {
        val trees = contentResolver.persistedUriPermissions.filter { it.isReadPermission }.mapNotNull { p -> folderPath(p.uri)?.let { it to p.uri } }
        var changed = 0
        val kept = HashSet<String>()
        for (folder in folders) {
            val (root, tree) = trees.firstOrNull { folder == it.first || folder.startsWith(it.first + "/") } ?: continue
            val top = DocumentsContract.getTreeDocumentId(tree)
            val rel = folder.removePrefix(root).trim('/')
            val id = if (rel.isEmpty()) top else if (top.endsWith(":")) top + rel else "$top/$rel"
            val cols = arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID, DocumentsContract.Document.COLUMN_DISPLAY_NAME)
            runCatching {
                contentResolver.query(DocumentsContract.buildChildDocumentsUriUsingTree(tree, id), cols, null, null, null)?.use { c ->
                    while (c.moveToNext()) {
                        val name = c.getString(1) ?: continue
                        if (name.substringAfterLast('.', "").lowercase() !in setOf("lrc", "cue")) continue
                        val out = File(dest + folder, name)
                        kept += out.path
                        val bytes = contentResolver.openInputStream(DocumentsContract.buildDocumentUriUsingTree(tree, c.getString(0)))?.use { it.readBytes() } ?: continue
                        if (out.exists() && out.readBytes().contentEquals(bytes)) continue
                        out.parentFile?.mkdirs()
                        out.writeBytes(bytes)
                        changed++
                    }
                }
            }
        }
        File(dest).walkBottomUp().forEach { if (it.isFile && it.path !in kept && it.delete()) changed++ }
        return changed
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

    private companion object {
        // Dart sends these once per change; they outlive this activity (the engine does too).
        var lockAllowed = false // "Show on lock screen" is on and music plays
        var keepOn = false // Disc mode or the lock-screen view is open while music plays

        const val PICK = 7301
        const val SAVE = 7302
        const val MUSIC = 1
        const val PHOTOS = 2
        const val NOTIFY = 3
    }
}
