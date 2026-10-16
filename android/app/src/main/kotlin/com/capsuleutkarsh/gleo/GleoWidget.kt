package com.capsuleutkarsh.gleo

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.widget.RemoteViews
import com.ryanheise.audioservice.AudioServicePlugin
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel

/// The home-screen widget: cover, title, artist, previous / play-pause / next. Dart sends the song and play
/// state ("widget" on gleo/android); the buttons go back to Dart's engine while Gleo runs. When Gleo isn't
/// running, every part of the widget opens Gleo.
class GleoWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) = render(context)

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        val button = intent.getStringExtra(BUTTON) ?: return
        val engine = FlutterEngineCache.getInstance().get(AudioServicePlugin.getFlutterEngineId())
        if (engine != null) MethodChannel(engine.dartExecutor.binaryMessenger, "gleo/android").invokeMethod("button", button)
        else { // Gleo was closed: open it (Android may refuse from the background; then the widget's next tap opens it)
            render(context)
            runCatching { context.startActivity(launch(context).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
        }
    }

    companion object {
        private const val BUTTON = "button"

        private fun launch(context: Context) =
            Intent(context, MainActivity::class.java).setAction(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)

        fun update(context: Context, song: Map<*, *>) {
            context.getSharedPreferences("widget", Context.MODE_PRIVATE).edit()
                .putString("title", song["title"] as String?)
                .putString("artist", song["artist"] as String?)
                .putString("art", song["art"] as String?)
                .putBoolean("playing", song["playing"] == true)
                .apply()
            render(context)
        }

        fun render(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, GleoWidget::class.java))
            if (ids.isEmpty()) return
            val alive = FlutterEngineCache.getInstance().get(AudioServicePlugin.getFlutterEngineId()) != null
            val prefs = context.getSharedPreferences("widget", Context.MODE_PRIVATE)
            val playing = alive && prefs.getBoolean("playing", false)
            val title = prefs.getString("title", null)
            val open = PendingIntent.getActivity(
                context, 0,
                launch(context),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            fun press(name: String, code: Int) = if (!alive) open else PendingIntent.getBroadcast(
                context, code, Intent(context, GleoWidget::class.java).putExtra(BUTTON, name),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            val views = RemoteViews(context.packageName, R.layout.widget).apply {
                setTextViewText(R.id.title, if (alive && !title.isNullOrEmpty()) title else "Gleo")
                setTextViewText(R.id.artist, if (alive && !title.isNullOrEmpty()) prefs.getString("artist", "") else "Tap to open")
                val art = prefs.getString("art", null)?.takeIf { alive && it.isNotEmpty() }
                    ?.let { BitmapFactory.decodeFile(it, BitmapFactory.Options().apply { inSampleSize = 2 }) }
                if (art != null) setImageViewBitmap(R.id.cover, art) else setImageViewResource(R.id.cover, R.mipmap.ic_launcher)
                setImageViewResource(R.id.play, if (playing) R.drawable.widget_pause else R.drawable.widget_play)
                setContentDescription(R.id.play, if (playing) "Pause" else "Play")
                setOnClickPendingIntent(R.id.cover, open)
                setOnClickPendingIntent(R.id.text, open)
                setOnClickPendingIntent(R.id.prev, press("previous", 1))
                setOnClickPendingIntent(R.id.play, press("toggle", 2))
                setOnClickPendingIntent(R.id.next, press("next", 3))
            }
            manager.updateAppWidget(ids, views)
        }
    }
}
