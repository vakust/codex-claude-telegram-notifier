package com.vakust.notifierv3

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.AssistChip
import androidx.compose.material3.AssistChipDefaults
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.vakust.notifierv3.ui.AppViewModel
import com.vakust.notifierv3.ui.ConnectionState

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            MaterialTheme {
                Surface(modifier = Modifier.fillMaxSize()) {
                    NotifierScreen()
                }
            }
        }
    }
}

@Composable
private fun NotifierScreen(vm: AppViewModel = viewModel()) {
    var apiUrl by remember { mutableStateOf(vm.apiUrl) }
    var token by remember { mutableStateOf(vm.token) }

    LaunchedEffect(Unit) {
        vm.bootstrap()
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Text("Notifier V3 Android", style = MaterialTheme.typography.titleLarge)

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            AssistChip(
                onClick = { vm.checkConnection() },
                label = { Text(connectionLabel(vm.connectionState)) },
                colors = AssistChipDefaults.assistChipColors(
                    containerColor = connectionColor(vm.connectionState)
                )
            )
            Text(
                text = if (vm.isBusy) "Running..." else "Idle",
                style = MaterialTheme.typography.bodyMedium
            )
        }

        OutlinedTextField(
            value = apiUrl,
            onValueChange = {
                apiUrl = it
                vm.updateApiUrl(it)
            },
            modifier = Modifier.fillMaxWidth(),
            label = { Text("API URL") }
        )

        OutlinedTextField(
            value = token,
            onValueChange = {
                token = it
                vm.updateToken(it)
            },
            modifier = Modifier.fillMaxWidth(),
            label = { Text("Mobile Token") }
        )

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Button(
                onClick = { vm.refreshFeed() },
                enabled = !vm.isBusy,
                modifier = Modifier.weight(1f)
            ) { Text("Refresh") }
            Button(
                onClick = { vm.sendCommand("codex", "continue") },
                enabled = !vm.isBusy,
                modifier = Modifier.weight(1f)
            ) { Text("Codex Continue") }
            Button(
                onClick = { vm.sendCommand("cc", "continue") },
                enabled = !vm.isBusy,
                modifier = Modifier.weight(1f)
            ) { Text("CC Continue") }
        }

        Text("Status: ${vm.statusText}", style = MaterialTheme.typography.bodyMedium)

        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            verticalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            items(vm.events) { item ->
                Text(
                    text = "${item.ts} | ${item.source}:${item.type}",
                    style = MaterialTheme.typography.bodySmall
                )
            }
        }
    }
}

private fun connectionLabel(state: ConnectionState): String =
    when (state) {
        ConnectionState.CONNECTED -> "Backend: Connected"
        ConnectionState.ERROR -> "Backend: Error"
        ConnectionState.UNKNOWN -> "Backend: Unknown"
    }

private fun connectionColor(state: ConnectionState): Color =
    when (state) {
        ConnectionState.CONNECTED -> Color(0xFFA5D6A7)
        ConnectionState.ERROR -> Color(0xFFEF9A9A)
        ConnectionState.UNKNOWN -> Color(0xFFE0E0E0)
    }
