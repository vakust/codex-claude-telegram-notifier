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

    fun getRefreshToken(defaultValue: String = ""): String =
        prefs.getString(KEY_REFRESH_TOKEN, defaultValue) ?: defaultValue

    fun setRefreshToken(value: String) {
        prefs.edit().putString(KEY_REFRESH_TOKEN, value).apply()
    }

    fun getWorkspaceId(defaultValue: String = ""): String =
        prefs.getString(KEY_WORKSPACE_ID, defaultValue) ?: defaultValue

    fun setWorkspaceId(value: String) {
        prefs.edit().putString(KEY_WORKSPACE_ID, value).apply()
    }

    fun getNotificationsEnabled(defaultValue: Boolean = true): Boolean =
        prefs.getBoolean(KEY_NOTIFICATIONS_ENABLED, defaultValue)

    fun setNotificationsEnabled(value: Boolean) {
        prefs.edit().putBoolean(KEY_NOTIFICATIONS_ENABLED, value).apply()
    }

    fun getSoundEnabled(defaultValue: Boolean = true): Boolean =
        prefs.getBoolean(KEY_SOUND_ENABLED, defaultValue)

    fun setSoundEnabled(value: Boolean) {
        prefs.edit().putBoolean(KEY_SOUND_ENABLED, value).apply()
    }

    fun getLastSeenEventId(defaultValue: String = ""): String =
        prefs.getString(KEY_LAST_SEEN_EVENT_ID, defaultValue) ?: defaultValue

    fun setLastSeenEventId(value: String) {
        prefs.edit().putString(KEY_LAST_SEEN_EVENT_ID, value).apply()
    }

    private companion object {
        private const val KEY_API_URL = "api_url"
        private const val KEY_TOKEN = "mobile_token"
        private const val KEY_REFRESH_TOKEN = "refresh_token"
        private const val KEY_WORKSPACE_ID = "workspace_id"
        private const val KEY_NOTIFICATIONS_ENABLED = "notifications_enabled"
        private const val KEY_SOUND_ENABLED = "sound_enabled"
        private const val KEY_LAST_SEEN_EVENT_ID = "last_seen_event_id"
    }
}
