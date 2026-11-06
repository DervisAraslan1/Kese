package dev.kese.kese

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.graphics.Color
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

class KeseWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        fun color(key: String, fallback: String) =
            Color.parseColor(widgetData.getString(key, null) ?: fallback)

        fun open(uri: String) =
            HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, Uri.parse(uri))

        val views = RemoteViews(context.packageName, R.layout.kese_widget).apply {
            setTextViewText(R.id.widget_title, widgetData.getString("title", null) ?: "Kese")
            setTextViewText(R.id.widget_amount, widgetData.getString("amount", null) ?: "")
            setTextColor(R.id.widget_title, color("inkSoft", "#A9B8D8"))
            setTextColor(R.id.widget_amount, color("ink", "#EEF3FF"))
            setInt(R.id.widget_background, "setColorFilter", color("background", "#101B36"))
            setInt(R.id.widget_add_circle, "setColorFilter", color("accent", "#6EA8FF"))
            setInt(R.id.widget_add_icon, "setColorFilter", color("onAccent", "#07122B"))
            setOnClickPendingIntent(R.id.widget_root, open("kese://ac"))
            setOnClickPendingIntent(R.id.widget_add, open("kese://ekle"))
        }
        appWidgetManager.updateAppWidget(appWidgetIds, views)
    }
}
