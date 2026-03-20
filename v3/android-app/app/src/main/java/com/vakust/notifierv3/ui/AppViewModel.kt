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
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class AppViewModel(application: Application) : AndroidViewModel(application) {
    private val api = ApiClient()
    private val settings = SettingsStore(application.applicationContext)
    private val notifier = EventNotifier(application.applicationContext)

    var apiUrl by mutableStateOf(settings.getApiUrl(DEFAULT_API_URL))
        private set
    var token by mutableStateOf(settings.getToken(DEFAULT_TOKEN))
        private set
    var workspaceId by mutableStateOf(settings.getWorkspaceId(""))
        private set
    var statusText by mutableStateOf("Ready")
        private set
    var connectionState by mutableStateOf(ConnectionState.UNKNOWN)
        private set
    var isBusy by mutableStateOf(false)
        private set
    var events by mutableStateOf<List<EventItem>>(emptyList())
        private set
    var notificationsEnabled by mutableStateOf(settings.getNotificationsEnabled(true))
        private set
    var soundEnabled by mutableStateOf(settings.getSoundEnabled(true))
        private set
    var notificationsPermissionGranted by mutableStateOf(notifier.notificationsPermissionGranted())
        private set
    private var pollingJob: Job? = null
    private var feedPrimed = false
    private val seenEventKeys = LinkedHashSet<String>()

    fun bootstrap() {
        viewModelScope.launch {
            val resolved = runCatching { withContext(Dispatchers.IO) { resolveWorkingApiUrl(apiUrl) } }.getOrNull()
            if (resolved != null && resolved != apiUrl) {
                updateApiUrl(resolved)
            }
            // If we already have a refresh token from previous pairing, try to renew access token.
            runCatching { refreshAccessTokenIfPossible() }.onFailure {
                // Keep going with current token / manual mode.
            }
            refreshNotificationPermissionState()
            checkConnection()
            refreshFeedInternal(background = false)
            ensurePolling()
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

    fun pairWithCode(pairCode: String) {
        if (pairCode.isBlank()) {
            statusText = "Pair code is empty."
            return
        }

        viewModelScope.launch {
            isBusy = true
            runCatching {
                withContext(Dispatchers.IO) { api.startPair(apiUrl, pairCode.trim()) }
            }.onSuccess { session ->
                if (!session.ok || session.access_token.isBlank()) {
                    connectionState = ConnectionState.ERROR
                    statusText = "Pair failed: invalid response."
                } else {
                    updateToken(session.access_token)
                    settings.setRefreshToken(session.refresh_token)
                    settings.setWorkspaceId(session.workspace_id)
                    workspaceId = session.workspace_id
                    connectionState = ConnectionState.CONNECTED
                    statusText = "Paired with workspace: ${session.workspace_id}"
                    refreshFeed()
                }
            }.onFailure { err ->
                connectionState = ConnectionState.ERROR
                statusText = "Pair failed: ${err.message}"
            }
            isBusy = false
        }
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

    fun refreshFeed(background: Boolean = false) {
        viewModelScope.launch {
            refreshFeedInternal(background = background)
        }
    }

    fun sendCommand(target: String, action: String, customText: String? = null) {
        viewModelScope.launch {
            isBusy = true
            runCatching {
                val metadata = mutableMapOf<String, Any?>()
                if (!customText.isNullOrBlank()) {
                    metadata["custom_text"] = customText
                }
                runWithAccessRetry { currentToken ->
                    withContext(Dispatchers.IO) { api.sendCommand(apiUrl, currentToken, target, action, metadata) }
                }
            }.onSuccess { resp ->
                connectionState = ConnectionState.CONNECTED
                statusText = "Accepted: ${resp.command_id}"
                refreshFeedInternal(background = true)
            }.onFailure { err ->
                connectionState = ConnectionState.ERROR
                statusText = "Command failed: ${err.message}"
            }
            isBusy = false
        }
    }

    fun updateNotificationsEnabled(value: Boolean) {
        notificationsEnabled = value
        settings.setNotificationsEnabled(value)
    }

    fun updateSoundEnabled(value: Boolean) {
        soundEnabled = value
        settings.setSoundEnabled(value)
    }

    fun refreshNotificationPermissionState() {
        notificationsPermissionGranted = notifier.notificationsPermissionGranted()
    }

    fun onNotificationPermissionResult(granted: Boolean) {
        notificationsPermissionGranted = granted
        statusText = if (granted) "Notification permission granted." else "Notification permission denied."
    }

    fun sendTestNotification() {
        if (!notificationsEnabled) {
            statusText = "Notifications are disabled."
            return
        }
        refreshNotificationPermissionState()
        if (!notificationsPermissionGranted) {
            statusText = "Grant notification permission first."
            return
        }
        val item = EventItem(
            event_id = "local-test-${System.currentTimeMillis()}",
            ts = java.time.Instant.now().toString(),
            source = "codex",
            type = "done",
            payload = mapOf("text" to "Test notification from Notifier V3")
        )
        notifier.postEventNotification(item, soundEnabled)
        statusText = if (soundEnabled) {
            "Test notification sent (sound ON)."
        } else {
            "Test notification sent (sound OFF)."
        }
    }

    private suspend fun refreshFeedInternal(background: Boolean) {
        if (!background) isBusy = true
        runCatching {
            runWithAccessRetry { currentToken ->
                withContext(Dispatchers.IO) { api.fetchFeed(apiUrl, currentToken, 20) }
            }
        }.onSuccess { feed ->
            handleEventNotifications(feed.items)
            events = feed.items
            connectionState = ConnectionState.CONNECTED
            if (!background) {
                statusText = "Feed loaded: ${feed.items.size}"
            }
        }.onFailure { err ->
            connectionState = ConnectionState.ERROR
            if (!background) {
                statusText = "Feed failed: ${err.message}"
            }
        }
        if (!background) isBusy = false
    }

    private fun handleEventNotifications(items: List<EventItem>) {
        if (items.isEmpty()) return

        if (!feedPrimed) {
            items.forEach { seenEventKeys += eventKey(it) }
            trimSeenEventKeys()
            feedPrimed = true
            persistNewestEventId(items)
            return
        }

        val fresh = items.filter { item -> seenEventKeys.contains(eventKey(item)).not() }
        if (fresh.isEmpty()) {
            persistNewestEventId(items)
            return
        }

        fresh.forEach { seenEventKeys += eventKey(it) }
        trimSeenEventKeys()
        persistNewestEventId(items)

        if (!notificationsEnabled) return
        refreshNotificationPermissionState()
        if (!notificationsPermissionGranted) return

        fresh
            .filter { shouldNotify(it) }
            .forEach { notifier.postEventNotification(it, soundEnabled) }
    }

    private fun shouldNotify(item: EventItem): Boolean {
        return when (item.type.lowercase()) {
            "done", "last_text", "command_failed" -> true
            else -> false
        }
    }

    private fun eventKey(item: EventItem): String {
        return if (item.event_id.isNotBlank()) item.event_id else "${item.ts}|${item.source}|${item.type}"
    }

    private fun trimSeenEventKeys(maxSize: Int = 500) {
        while (seenEventKeys.size > maxSize) {
            val first = seenEventKeys.firstOrNull() ?: return
            seenEventKeys.remove(first)
        }
    }

    private fun persistNewestEventId(items: List<EventItem>) {
        val newest = items.lastOrNull()?.event_id?.takeIf { it.isNotBlank() } ?: return
        settings.setLastSeenEventId(newest)
    }

    private fun ensurePolling() {
        if (pollingJob?.isActive == true) return
        pollingJob = viewModelScope.launch {
            while (isActive) {
                delay(3500)
                if (token.isNotBlank()) {
                    refreshFeedInternal(background = true)
                }
            }
        }
    }

    override fun onCleared() {
        pollingJob?.cancel()
        super.onCleared()
    }

    private suspend fun <T> runWithAccessRetry(block: suspend (String) -> T): T {
        try {
            return block(token)
        } catch (first: Exception) {
            if (!isUnauthorized(first)) throw first
            val refreshed = refreshAccessTokenIfPossible()
            if (!refreshed) throw first
            return block(token)
        }
    }

    private suspend fun refreshAccessTokenIfPossible(): Boolean {
        val refreshToken = settings.getRefreshToken("")
        if (refreshToken.isBlank()) return false

        val session = withContext(Dispatchers.IO) { api.refreshSession(apiUrl, refreshToken) }
        if (!session.ok || session.access_token.isBlank()) return false

        updateToken(session.access_token)
        settings.setRefreshToken(session.refresh_token)
        settings.setWorkspaceId(session.workspace_id)
        workspaceId = session.workspace_id
        return true
    }

    private fun isUnauthorized(err: Exception): Boolean {
        val msg = err.message ?: return false
        return msg.contains("HTTP 401")
    }

    private fun resolveWorkingApiUrl(preferred: String): String? {
        val candidates = linkedSetOf(preferred, "http://127.0.0.1:8787", "http://10.0.2.2:8787")
        for (candidate in candidates) {
            val ok = runCatching { api.checkHealth(candidate) }.getOrDefault(false)
            if (ok) return candidate
        }
        return null
    }

    companion object {
        private const val DEFAULT_API_URL = "http://127.0.0.1:8787"
        private const val DEFAULT_TOKEN = "dev-mobile-token"
    }
}

enum class ConnectionState {
    UNKNOWN,
    CONNECTED,
    ERROR
}
