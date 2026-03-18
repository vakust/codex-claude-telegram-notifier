package com.vakust.notifierv3.model

data class EventItem(
    val event_id: String,
    val ts: String,
    val source: String,
    val type: String,
    val payload: Map<String, Any?>
)

data class FeedResponse(
    val ok: Boolean,
    val items: List<EventItem>,
    val next_cursor: String?
)

data class CommandResponse(
    val ok: Boolean,
    val command_id: String,
    val status: String
)
