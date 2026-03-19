package com.vakust.notifierv3.ui

import android.app.Application
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.vakust.notifierv3.model.EventItem
import com.vakust.notifierv3.net.ApiClient
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class AppViewModel(application: Application) : AndroidViewModel(application) {
    private val api = ApiClient()
    private val settings = SettingsStore(application.applicationContext)

    var apiUrl by mutableStateOf(settings.getApiUrl(DEFAULT_API_URL))
        private set
    var token by mutableStateOf(settings.getToken(DEFAULT_TOKEN))
        private set
    var statusText by mutableStateOf("Ready")
        private set
    var connectionState by mutableStateOf(ConnectionState.UNKNOWN)
        private set
    var isBusy by mutableStateOf(false)
        private set
    var events by mutableStateOf<List<EventItem>>(emptyList())
        private set

    fun bootstrap() {
        viewModelScope.launch {
            val resolved = runCatching { withContext(Dispatchers.IO) { resolveWorkingApiUrl(apiUrl) } }.getOrNull()
            if (resolved != null && resolved != apiUrl) {
                updateApiUrl(resolved)
            }
            checkConnection()
            refreshFeed()
        }
    }

    fun updateApiUrl(value: String) {
        apiUrl = value
        settings.setApiUrl(value)
    }

    fun updateToken(value: String) {
        token = value
        settings.setToken(value)
    }

    fun checkConnection() {
        viewModelScope.launch {
            runCatching { withContext(Dispatchers.IO) { resolveWorkingApiUrl(apiUrl) } }
                .onSuccess { resolved ->
                    if (resolved == null) {
                        connectionState = ConnectionState.ERROR
                        statusText = "Connection failed: backend not reachable."
                        return@onSuccess
                    }
                    if (resolved != apiUrl) {
                        updateApiUrl(resolved)
                        statusText = "Backend reachable via $resolved (auto switched)."
                    } else {
                        statusText = "Backend is reachable."
                    }
                    connectionState = ConnectionState.CONNECTED
                }.onFailure { err ->
                    connectionState = ConnectionState.ERROR
                    statusText = "Connection failed: ${err.message}"
                }
        }
    }

    fun refreshFeed() {
        viewModelScope.launch {
            isBusy = true
            runCatching { withContext(Dispatchers.IO) { api.fetchFeed(apiUrl, token, 20) } }
                .onSuccess { feed ->
                    events = feed.items
                    connectionState = ConnectionState.CONNECTED
                    statusText = "Feed loaded: ${feed.items.size}"
                }
                .onFailure { err ->
                    connectionState = ConnectionState.ERROR
                    statusText = "Feed failed: ${err.message}"
                }
            isBusy = false
        }
    }

    fun sendCommand(target: String, action: String) {
        viewModelScope.launch {
            isBusy = true
            runCatching { withContext(Dispatchers.IO) { api.sendCommand(apiUrl, token, target, action) } }
                .onSuccess { resp ->
                    connectionState = ConnectionState.CONNECTED
                    statusText = "Accepted: ${resp.command_id}"
                    refreshFeed()
                }
                .onFailure { err ->
                    connectionState = ConnectionState.ERROR
                    statusText = "Command failed: ${err.message}"
                }
            isBusy = false
        }
    }

    companion object {
        private const val DEFAULT_API_URL = "http://127.0.0.1:8787"
        private const val DEFAULT_TOKEN = "dev-mobile-token"
    }

    private fun resolveWorkingApiUrl(preferred: String): String? {
        val candidates = linkedSetOf(preferred, "http://127.0.0.1:8787", "http://10.0.2.2:8787")
        for (candidate in candidates) {
            val ok = runCatching { api.checkHealth(candidate) }.getOrDefault(false)
            if (ok) return candidate
        }
        return null
    }
}

enum class ConnectionState {
    UNKNOWN,
    CONNECTED,
    ERROR
}
