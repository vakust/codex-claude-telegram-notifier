package com.vakust.notifierv3

import android.Manifest
import android.graphics.BitmapFactory
import android.os.Build
import android.os.Bundle
import android.util.Base64
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.rememberTransformableState
import androidx.compose.foundation.gestures.transformable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Tab
import androidx.compose.material3.TabRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.lifecycle.viewmodel.compose.viewModel
import coil.compose.AsyncImage
import com.vakust.notifierv3.ui.AppViewModel

private data class ScreenTab(
    val title: String,
    val sourceFilter: String?
)

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
    var pairCode by remember { mutableStateOf("") }
    var codexCustomText by rememberSaveable { mutableStateOf("") }
    var ccCustomText by rememberSaveable { mutableStateOf("") }
    var showSettings by rememberSaveable { mutableStateOf(false) }
    var showControls by rememberSaveable { mutableStateOf(false) }
    var zoomImage by remember { mutableStateOf<ZoomImage?>(null) }
    var selectedTabIndex by rememberSaveable { mutableStateOf(0) }
    var topMenuOpen by rememberSaveable { mutableStateOf(false) }
    val notificationPermissionLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestPermission()
    ) { granted ->
        vm.onNotificationPermissionResult(granted)
    }
    val focusManager = LocalFocusManager.current
    val keyboardController = LocalSoftwareKeyboardController.current

    val tabs = remember {
        listOf(
            ScreenTab("Codex", "codex"),
            ScreenTab("Cloud Code", "cc"),
            ScreenTab("All", null)
        )
    }

    val feedListState = rememberLazyListState()
    val newestEventKey = remember(vm.events) {
        vm.events.lastOrNull()?.let {
            if (it.event_id.isNotBlank()) it.event_id else "${it.ts}-${it.source}-${it.type}"
        }
    }
    val visibleEvents = remember(vm.events, selectedTabIndex) {
        val selected = tabs[selectedTabIndex]
        val all = vm.events.asReversed()
        val filter = selected.sourceFilter
        if (filter == null) all
        else all.filter { it.source.equals(filter, ignoreCase = true) }
    }

    LaunchedEffect(Unit) {
        vm.bootstrap()
    }

    LaunchedEffect(newestEventKey) {
        if (newestEventKey != null) {
            feedListState.animateScrollToItem(0)
        }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .pointerInput(Unit) {
                detectTapGestures(
                    onTap = {
                        focusManager.clearFocus(force = true)
                        keyboardController?.hide()
                    }
                )
            }
            .background(
                Brush.verticalGradient(
                    colors = listOf(Color(0xFFF8FAFF), Color(0xFFEAF2FF))
                )
            )
            .padding(12.dp)
    ) {
        Column(
            modifier = Modifier.fillMaxSize(),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Card(
                shape = RoundedCornerShape(14.dp),
                colors = CardDefaults.cardColors(containerColor = Color.White.copy(alpha = 0.95f))
            ) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 10.dp, vertical = 4.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Text(
                        text = "Notifications",
                        style = MaterialTheme.typography.labelSmall,
                        color = Color(0xFF37474F),
                        fontWeight = FontWeight.SemiBold
                    )
                    Text(
                        text = "${vm.events.size}",
                        style = MaterialTheme.typography.labelSmall,
                        color = Color(0xFF607D8B),
                        modifier = Modifier.weight(1f)
                    )

                    Box {
                        TextButton(onClick = { topMenuOpen = true }) {
                            Text("Menu")
                        }
                        DropdownMenu(
                            expanded = topMenuOpen,
                            onDismissRequest = { topMenuOpen = false }
                        ) {
                            DropdownMenuItem(
                                text = { Text("Refresh Feed") },
                                onClick = {
                                    topMenuOpen = false
                                    vm.refreshFeed()
                                }
                            )
                            DropdownMenuItem(
                                text = { Text("Check Backend") },
                                onClick = {
                                    topMenuOpen = false
                                    vm.checkConnection()
                                }
                            )
                            DropdownMenuItem(
                                text = { Text("Notifications: ${if (vm.notificationsEnabled) "On" else "Off"}") },
                                onClick = {
                                    topMenuOpen = false
                                    vm.updateNotificationsEnabled(!vm.notificationsEnabled)
                                }
                            )
                            DropdownMenuItem(
                                text = { Text("Sound: ${if (vm.soundEnabled) "On" else "Off"}") },
                                onClick = {
                                    topMenuOpen = false
                                    vm.updateSoundEnabled(!vm.soundEnabled)
                                }
                            )
                            DropdownMenuItem(
                                text = { Text("Test Notification") },
                                onClick = {
                                    topMenuOpen = false
                                    vm.sendTestNotification()
                                }
                            )
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                                DropdownMenuItem(
                                    text = {
                                        Text(
                                            if (vm.notificationsPermissionGranted) {
                                                "Permission: Granted"
                                            } else {
                                                "Grant notification permission"
                                            }
                                        )
                                    },
                                    onClick = {
                                        topMenuOpen = false
                                        if (vm.notificationsPermissionGranted) {
                                            vm.refreshNotificationPermissionState()
                                        } else {
                                            notificationPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
                                        }
                                    }
                                )
                            }
                            DropdownMenuItem(
                                text = { Text(if (showSettings) "Hide Settings" else "Show Settings") },
                                onClick = {
                                    topMenuOpen = false
                                    showSettings = !showSettings
                                }
                            )
                            DropdownMenuItem(
                                text = { Text(if (showControls) "Hide Controls" else "Show Controls") },
                                onClick = {
                                    topMenuOpen = false
                                    showControls = !showControls
                                }
                            )
                        }
                    }
                }
            }

            if (showSettings) {
                Card(
                    shape = RoundedCornerShape(14.dp),
                    colors = CardDefaults.cardColors(containerColor = Color.White.copy(alpha = 0.92f))
                ) {
                    Column(
                        modifier = Modifier.padding(12.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        OutlinedTextField(
                            value = vm.apiUrl,
                            onValueChange = { vm.updateApiUrl(it) },
                            modifier = Modifier.fillMaxWidth(),
                            label = { Text("API URL") },
                            singleLine = true,
                            maxLines = 1
                        )

                        OutlinedTextField(
                            value = vm.token,
                            onValueChange = { vm.updateToken(it) },
                            modifier = Modifier.fillMaxWidth(),
                            label = { Text("Mobile Token") },
                            singleLine = true,
                            maxLines = 1
                        )

                        OutlinedTextField(
                            value = pairCode,
                            onValueChange = { pairCode = it },
                            modifier = Modifier.fillMaxWidth(),
                            label = { Text("Pair Code (e.g. 123-456)") },
                            singleLine = true,
                            maxLines = 1
                        )

                        Button(
                            onClick = { vm.pairWithCode(pairCode) },
                            enabled = !vm.isBusy,
                            modifier = Modifier.fillMaxWidth()
                        ) { Text("Pair Device") }
                    }
                }
            }

            Card(
                shape = RoundedCornerShape(14.dp),
                colors = CardDefaults.cardColors(containerColor = Color.White.copy(alpha = 0.95f))
            ) {
                Column(
                    modifier = Modifier.padding(4.dp),
                    verticalArrangement = Arrangement.spacedBy(4.dp)
                ) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            text = "Controls",
                            style = MaterialTheme.typography.labelMedium,
                            modifier = Modifier.weight(1f)
                        )
                        TextButton(onClick = { showControls = !showControls }) {
                            Text(if (showControls) "Hide" else "Show")
                        }
                    }

                    if (showControls) {
                        TabRow(selectedTabIndex = selectedTabIndex) {
                            tabs.forEachIndexed { index, tab ->
                                Tab(
                                    selected = selectedTabIndex == index,
                                    onClick = { selectedTabIndex = index },
                                    text = { Text(tab.title, fontWeight = FontWeight.SemiBold) }
                                )
                            }
                        }

                        when (selectedTabIndex) {
                        0 -> {
                            Column(
                                modifier = Modifier.fillMaxWidth(),
                                verticalArrangement = Arrangement.spacedBy(4.dp)
                            ) {
                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    horizontalArrangement = Arrangement.spacedBy(6.dp)
                                ) {
                                    CompactActionButton(
                                        onClick = { vm.sendCommand("codex", "continue") },
                                        enabled = !vm.isBusy,
                                        text = "Continue",
                                        colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF1B5E20)),
                                        modifier = Modifier.weight(1f)
                                    )
                                    CompactActionButton(
                                        onClick = { vm.sendCommand("codex", "fix_retest") },
                                        enabled = !vm.isBusy,
                                        text = "Fix+Retest",
                                        colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF00695C)),
                                        modifier = Modifier.weight(1f)
                                    )
                                }

                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    horizontalArrangement = Arrangement.spacedBy(6.dp)
                                ) {
                                    CompactActionButton(
                                        onClick = { vm.sendCommand("codex", "shot") },
                                        enabled = !vm.isBusy,
                                        text = "Shot",
                                        colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF283593)),
                                        modifier = Modifier.weight(1f)
                                    )
                                    CompactActionButton(
                                        onClick = { vm.sendCommand("codex", "last_text") },
                                        enabled = !vm.isBusy,
                                        text = "Last Text",
                                        colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF5D4037)),
                                        modifier = Modifier.weight(1f)
                                    )
                                }
                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                                    verticalAlignment = Alignment.CenterVertically
                                ) {
                                    OutlinedTextField(
                                        value = codexCustomText,
                                        onValueChange = { codexCustomText = it },
                                        modifier = Modifier.weight(1f),
                                        label = { Text("Custom") },
                                        minLines = 1,
                                        maxLines = 2
                                    )
                                    CompactActionButton(
                                        onClick = {
                                            val text = codexCustomText.trim()
                                            if (text.isNotBlank()) {
                                                vm.sendCommand("codex", "custom", text)
                                                codexCustomText = ""
                                            }
                                        },
                                        enabled = !vm.isBusy && codexCustomText.trim().isNotEmpty(),
                                        text = "Send"
                                    )
                                }
                            }
                        }

                        1 -> {
                            Column(
                                modifier = Modifier.fillMaxWidth(),
                                verticalArrangement = Arrangement.spacedBy(4.dp)
                            ) {
                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    horizontalArrangement = Arrangement.spacedBy(6.dp)
                                ) {
                                    CompactActionButton(
                                        onClick = { vm.sendCommand("cc", "continue") },
                                        enabled = !vm.isBusy,
                                        text = "CC Continue",
                                        colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF6A1B9A)),
                                        modifier = Modifier.weight(1f)
                                    )
                                    CompactActionButton(
                                        onClick = { vm.sendCommand("cc", "fix_retest") },
                                        enabled = !vm.isBusy,
                                        text = "CC Fix+Retest",
                                        colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF4527A0)),
                                        modifier = Modifier.weight(1f)
                                    )
                                }

                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    horizontalArrangement = Arrangement.spacedBy(6.dp)
                                ) {
                                    CompactActionButton(
                                        onClick = { vm.sendCommand("cc", "shot") },
                                        enabled = !vm.isBusy,
                                        text = "Shot CC",
                                        colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF5E35B1)),
                                        modifier = Modifier.weight(1f)
                                    )
                                    CompactActionButton(
                                        onClick = { vm.sendCommand("cc", "last_text") },
                                        enabled = !vm.isBusy,
                                        text = "CC Last Text",
                                        colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF4E342E)),
                                        modifier = Modifier.weight(1f)
                                    )
                                }
                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                                    verticalAlignment = Alignment.CenterVertically
                                ) {
                                    OutlinedTextField(
                                        value = ccCustomText,
                                        onValueChange = { ccCustomText = it },
                                        modifier = Modifier.weight(1f),
                                        label = { Text("Custom") },
                                        minLines = 1,
                                        maxLines = 2
                                    )
                                    CompactActionButton(
                                        onClick = {
                                            val text = ccCustomText.trim()
                                            if (text.isNotBlank()) {
                                                vm.sendCommand("cc", "custom", text)
                                                ccCustomText = ""
                                            }
                                        },
                                        enabled = !vm.isBusy && ccCustomText.trim().isNotEmpty(),
                                        text = "Send"
                                    )
                                }
                            }
                        }

                        else -> {
                            Column(
                                modifier = Modifier.fillMaxWidth(),
                                verticalArrangement = Arrangement.spacedBy(4.dp)
                            ) {
                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    horizontalArrangement = Arrangement.spacedBy(6.dp)
                                ) {
                                    CompactActionButton(
                                        onClick = { vm.sendCommand("codex", "shot") },
                                        enabled = !vm.isBusy,
                                        text = "Shot Codex",
                                        modifier = Modifier.weight(1f)
                                    )
                                    CompactActionButton(
                                        onClick = { vm.sendCommand("cc", "shot") },
                                        enabled = !vm.isBusy,
                                        text = "Shot CC",
                                        modifier = Modifier.weight(1f)
                                    )
                                }
                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    horizontalArrangement = Arrangement.spacedBy(6.dp)
                                ) {
                                    CompactActionButton(
                                        onClick = { vm.sendCommand("codex", "last_text") },
                                        enabled = !vm.isBusy,
                                        text = "Codex Last Text",
                                        modifier = Modifier.weight(1f)
                                    )
                                    CompactActionButton(
                                        onClick = { vm.sendCommand("cc", "last_text") },
                                        enabled = !vm.isBusy,
                                        text = "CC Last Text",
                                        modifier = Modifier.weight(1f)
                                    )
                                }
                            }
                        }
                        }
                    }
                }
            }

            LazyColumn(
                modifier = Modifier
                    .fillMaxWidth()
                    .weight(1f),
                state = feedListState,
                verticalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                if (visibleEvents.isEmpty()) {
                    item {
                        Card(
                            shape = RoundedCornerShape(12.dp),
                            colors = CardDefaults.cardColors(containerColor = Color.White.copy(alpha = 0.9f))
                        ) {
                            Text(
                                text = "No events in '${tabs[selectedTabIndex].title}' yet. Trigger an action and wait a few seconds.",
                                style = MaterialTheme.typography.bodySmall,
                                modifier = Modifier.padding(12.dp)
                            )
                        }
                    }
                }

                items(
                    items = visibleEvents,
                    key = { if (it.event_id.isBlank()) "${it.ts}-${it.source}-${it.type}" else it.event_id }
                ) { item ->
                    EventCard(
                        item = item,
                        apiUrl = vm.apiUrl,
                        onOpenImage = { url, bytes -> zoomImage = ZoomImage(url = url, bytes = bytes) }
                    )
                }
            }
        }
    }

    zoomImage?.let { image ->
        ZoomImageDialog(
            image = image,
            onDismiss = { zoomImage = null }
        )
    }
}

@Composable
private fun CompactActionButton(
    onClick: () -> Unit,
    text: String,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    colors: androidx.compose.material3.ButtonColors = ButtonDefaults.buttonColors()
) {
    Button(
        onClick = onClick,
        enabled = enabled,
        colors = colors,
        shape = RoundedCornerShape(10.dp),
        contentPadding = PaddingValues(horizontal = 8.dp, vertical = 4.dp),
        modifier = modifier.height(38.dp)
    ) {
        Text(text = text, maxLines = 1, softWrap = false)
    }
}

private fun displaySource(source: String): String {
    return when {
        source.equals("codex", ignoreCase = true) -> "Codex"
        source.equals("cc", ignoreCase = true) -> "Cloud Code"
        source.isBlank() -> "unknown"
        else -> source
    }
}

@Composable
private fun EventCard(
    item: com.vakust.notifierv3.model.EventItem,
    apiUrl: String,
    onOpenImage: (url: String?, bytes: ByteArray?) -> Unit
) {
    val payloadText = extractPayloadText(item.payload)
    val imageRef = resolveImageReference(item.payload, apiUrl)
    val base64Bytes = remember(imageRef) { decodeBase64Image(imageRef) }

    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(14.dp),
        colors = CardDefaults.cardColors(containerColor = Color.White.copy(alpha = 0.94f))
    ) {
        Column(
            modifier = Modifier.padding(10.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            Text(
                text = "${displaySource(item.source)} | ${item.type} | ${item.ts}",
                style = MaterialTheme.typography.labelMedium,
                color = Color(0xFF37474F)
            )

            if (payloadText.isNotBlank()) {
                Text(
                    text = payloadText,
                    style = MaterialTheme.typography.bodySmall
                )
            }

            when {
                imageRef != null && imageRef.startsWith("http", ignoreCase = true) -> {
                    AsyncImage(
                        model = imageRef,
                        contentDescription = "Event screenshot",
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(220.dp)
                            .background(Color.Black)
                            .clickable { onOpenImage(imageRef, null) },
                        contentScale = ContentScale.Fit
                    )
                }

                base64Bytes != null -> {
                    val bitmap = remember(base64Bytes) {
                        BitmapFactory.decodeByteArray(base64Bytes, 0, base64Bytes.size)
                    }
                    if (bitmap != null) {
                        Image(
                            bitmap = bitmap.asImageBitmap(),
                            contentDescription = "Event screenshot",
                            modifier = Modifier
                                .fillMaxWidth()
                                .height(220.dp)
                                .background(Color.Black)
                                .clickable { onOpenImage(null, base64Bytes) },
                            contentScale = ContentScale.Fit
                        )
                    }
                }
            }

            if (imageRef != null || base64Bytes != null) {
                Text(
                    text = "Tap screenshot to enlarge",
                    style = MaterialTheme.typography.labelSmall
                )
            }

            if (item.payload.isNotEmpty()) {
                Text(
                    text = "payload keys: ${item.payload.keys.joinToString(", ")}",
                    style = MaterialTheme.typography.labelSmall,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis
                )
            }
        }
    }
}

data class ZoomImage(
    val url: String? = null,
    val bytes: ByteArray? = null
)

@Composable
@OptIn(ExperimentalFoundationApi::class)
private fun ZoomImageDialog(image: ZoomImage, onDismiss: () -> Unit) {
    var scale by remember { mutableStateOf(1f) }
    var offset by remember { mutableStateOf(Offset.Zero) }

    val transformState = rememberTransformableState { zoomChange, panChange, _ ->
        val nextScale = (scale * zoomChange).coerceIn(1f, 5f)
        scale = nextScale
        offset = if (nextScale <= 1.01f) {
            Offset.Zero
        } else {
            offset + panChange
        }
    }

    val gestureModifier = Modifier
        .fillMaxSize()
        .clipToBounds()
        .pointerInput(image) {
            detectTapGestures(
                onDoubleTap = {
                    if (scale > 1.01f) {
                        scale = 1f
                        offset = Offset.Zero
                    } else {
                        scale = 2f
                    }
                },
                onLongPress = {
                    scale = 1f
                    offset = Offset.Zero
                }
            )
        }
        .transformable(
            state = transformState,
            canPan = { _ -> scale > 1.01f }
        )
        .background(Color.Black)
        .graphicsLayer {
            scaleX = scale
            scaleY = scale
            translationX = offset.x
            translationY = offset.y
        }

    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(usePlatformDefaultWidth = false)
    ) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(Color.Black)
        ) {
            when {
                image.url != null && image.url.startsWith("http", ignoreCase = true) -> {
                    AsyncImage(
                        model = image.url,
                        contentDescription = "Zoomed screenshot",
                        modifier = gestureModifier,
                        contentScale = ContentScale.Fit
                    )
                }

                image.bytes != null -> {
                    val bitmap = remember(image.bytes) {
                        BitmapFactory.decodeByteArray(image.bytes, 0, image.bytes.size)
                    }
                    if (bitmap != null) {
                        Image(
                            bitmap = bitmap.asImageBitmap(),
                            contentDescription = "Zoomed screenshot",
                            modifier = gestureModifier,
                            contentScale = ContentScale.Fit
                        )
                    }
                }
            }

            TextButton(
                onClick = onDismiss,
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(12.dp)
            ) {
                Text("Close", color = Color.White)
            }
        }
    }
}

private fun extractPayloadText(payload: Map<String, Any?>): String {
    val preferred = listOf("text", "message", "caption", "summary", "status", "note", "body")
    for (key in preferred) {
        val value = payload[key] ?: continue
        val out = value.toString().trim()
        if (out.isNotBlank()) return out
    }
    return payload.entries
        .take(3)
        .joinToString(" | ") { "${it.key}=${it.value}" }
}

private fun resolveImageReference(payload: Map<String, Any?>, apiUrl: String): String? {
    val preferred = listOf(
        "image_url", "screenshot_url", "photo_url", "url", "image", "screenshot", "photo", "file"
    )

    val values = mutableListOf<String>()
    preferred.forEach { key ->
        val value = payload[key]
        if (value is String && value.isNotBlank()) values += value.trim()
    }

    payload.entries.forEach { (key, value) ->
        val isImageLikeKey =
            key.contains("url", true) ||
                key.contains("image", true) ||
                key.contains("shot", true) ||
                key.contains("photo", true)
        if (value is String && isImageLikeKey) {
            if (value.isNotBlank()) values += value.trim()
        }
    }

    for (candidate in values.distinct()) {
        if (candidate.startsWith("http://", true) || candidate.startsWith("https://", true)) return candidate
        if (candidate.startsWith("data:image/", true)) return candidate
        if (candidate.startsWith("/")) return apiUrl.trimEnd('/') + candidate
        if (candidate.length > 200 && candidate.matches(Regex("^[A-Za-z0-9+/=\\r\\n]+$"))) return candidate
    }
    return null
}

private fun decodeBase64Image(value: String?): ByteArray? {
    if (value.isNullOrBlank()) return null
    val raw = when {
        value.startsWith("data:image/", true) -> value.substringAfter(",", "")
        else -> value
    }.trim()
    if (raw.length < 200) return null
    return runCatching { Base64.decode(raw, Base64.DEFAULT) }.getOrNull()
}
