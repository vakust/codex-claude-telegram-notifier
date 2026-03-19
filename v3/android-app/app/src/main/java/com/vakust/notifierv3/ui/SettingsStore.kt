package com.vakust.notifierv3.ui

import android.content.Context

class SettingsStore(context: Context) {
    private val prefs = context.getSharedPreferences("notifier_v3_settings", Context.MODE_PRIVATE)

    fun getApiUrl(defaultValue: String): String = prefs.getString(KEY_API_URL, defaultValue) ?: defaultValue

    fun getToken(defaultValue: String): String = prefs.getString(KEY_TOKEN, defaultValue) ?: defaultValue

    fun setApiUrl(value: String) {
        prefs.edit().putString(KEY_API_URL, value).apply()
    }

    fun setToken(value: String) {
        prefs.edit().putString(KEY_TOKEN, value).apply()
    }

    private companion object {
        private const val KEY_API_URL = "api_url"
        private const val KEY_TOKEN = "mobile_token"
    }
}
