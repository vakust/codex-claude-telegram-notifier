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
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.vakust.notifierv3.ui.AppViewModel

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

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Text("Notifier V3 Android", style = MaterialTheme.typography.titleLarge)

        OutlinedTextField(
            value = apiUrl,
            onValueChange = {
                apiUrl = it
                vm.apiUrl = it
            },
            modifier = Modifier.fillMaxWidth(),
            label = { Text("API URL") }
        )

        OutlinedTextField(
            value = token,
            onValueChange = {
                token = it
                vm.token = it
            },
            modifier = Modifier.fillMaxWidth(),
            label = { Text("Mobile Token") }
        )

        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Button(onClick = { vm.refreshFeed() }) { Text("Refresh") }
            Button(onClick = { vm.sendCommand("codex", "continue") }) { Text("Codex Continue") }
            Button(onClick = { vm.sendCommand("cc", "continue") }) { Text("CC Continue") }
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
