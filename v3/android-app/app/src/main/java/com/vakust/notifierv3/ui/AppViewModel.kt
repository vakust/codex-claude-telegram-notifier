package com.vakust.notifierv3.ui

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.vakust.notifierv3.model.EventItem
import com.vakust.notifierv3.net.ApiClient
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.Dispatchers

class AppViewModel(
    private val api: ApiClient = ApiClient()
) : ViewModel() {
    var apiUrl by mutableStateOf("http://10.0.2.2:8787")
    var token by mutableStateOf("dev-mobile-token")
    var statusText by mutableStateOf("Ready")
    var events by mutableStateOf<List<EventItem>>(emptyList())

    fun refreshFeed() {
        viewModelScope.launch {
            runCatching { withContext(Dispatchers.IO) { api.fetchFeed(apiUrl, token, 20) } }
                .onSuccess { feed ->
                    events = feed.items
                    statusText = "Feed loaded: ${feed.items.size}"
                }
                .onFailure { err ->
                    statusText = "Feed failed: ${err.message}"
                }
        }
    }

    fun sendCommand(target: String, action: String) {
        viewModelScope.launch {
            runCatching { withContext(Dispatchers.IO) { api.sendCommand(apiUrl, token, target, action) } }
                .onSuccess { resp ->
                    statusText = "Accepted: ${resp.command_id}"
                    refreshFeed()
                }
                .onFailure { err ->
                    statusText = "Command failed: ${err.message}"
                }
        }
    }
}
