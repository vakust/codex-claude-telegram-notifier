package com.vakust.notifierv3.net

import com.vakust.notifierv3.model.CommandResponse
import com.vakust.notifierv3.model.EventItem
import com.vakust.notifierv3.model.FeedResponse
import com.vakust.notifierv3.model.AuthSessionResponse
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedReader
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import java.time.Instant

class ApiClient {
    fun checkHealth(baseUrl: String): Boolean {
        val url = URL(baseUrl.trimEnd('/') + "/health")
        val conn = (url.openConnection() as HttpURLConnection).apply {
            requestMethod = "GET"
            connectTimeout = 2500
            readTimeout = 2500
            setRequestProperty("Accept", "application/json")
        }
        return conn.useResponse { body ->
            JSONObject(body).optBoolean("ok", false)
        }
    }

    fun fetchFeed(baseUrl: String, token: String, limit: Int = 30): FeedResponse {
        val url = URL(baseUrl.trimEnd('/') + "/v1/mobile/feed?limit=$limit")
        val conn = (url.openConnection() as HttpURLConnection).apply {
            requestMethod = "GET"
            connectTimeout = 6000
            readTimeout = 6000
            setRequestProperty("Authorization", "Bearer $token")
            setRequestProperty("Accept", "application/json")
        }
        return conn.useResponse { body ->
            val json = JSONObject(body)
            val items = json.optJSONArray("items") ?: JSONArray()
            FeedResponse(
                ok = json.optBoolean("ok", false),
                items = parseItems(items),
                next_cursor = json.optString("next_cursor", "").ifBlank { null }
            )
        }
    }

    fun startPair(baseUrl: String, pairCode: String): AuthSessionResponse {
        val url = URL(baseUrl.trimEnd('/') + "/v1/mobile/pair/start")
        val payload = JSONObject(mapOf("pair_code" to pairCode))
        val conn = (url.openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            doOutput = true
            connectTimeout = 6000
            readTimeout = 6000
            setRequestProperty("Content-Type", "application/json")
            setRequestProperty("Accept", "application/json")
        }
        OutputStreamWriter(conn.outputStream, Charsets.UTF_8).use { it.write(payload.toString()) }
        return conn.useResponse { body ->
            parseAuthSession(JSONObject(body))
        }
    }

    fun refreshSession(baseUrl: String, refreshToken: String): AuthSessionResponse {
        val url = URL(baseUrl.trimEnd('/') + "/v1/mobile/auth/refresh")
        val payload = JSONObject(mapOf("refresh_token" to refreshToken))
        val conn = (url.openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            doOutput = true
            connectTimeout = 6000
            readTimeout = 6000
            setRequestProperty("Content-Type", "application/json")
            setRequestProperty("Accept", "application/json")
        }
        OutputStreamWriter(conn.outputStream, Charsets.UTF_8).use { it.write(payload.toString()) }
        return conn.useResponse { body ->
            parseAuthSession(JSONObject(body))
        }
    }

    fun sendCommand(baseUrl: String, token: String, target: String, action: String): CommandResponse {
        val url = URL(baseUrl.trimEnd('/') + "/v1/mobile/commands")
        val payload = JSONObject(
            mapOf(
                "target" to target,
                "action" to action,
                "metadata" to mapOf(
                    "client" to "android-app",
                    "ts" to Instant.now().toString()
                )
            )
        )

        val conn = (url.openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            doOutput = true
            connectTimeout = 6000
            readTimeout = 6000
            setRequestProperty("Authorization", "Bearer $token")
            setRequestProperty("Content-Type", "application/json")
            setRequestProperty("Accept", "application/json")
        }

        OutputStreamWriter(conn.outputStream, Charsets.UTF_8).use { it.write(payload.toString()) }
        return conn.useResponse { body ->
            val json = JSONObject(body)
            CommandResponse(
                ok = json.optBoolean("ok", false),
                command_id = json.optString("command_id", ""),
                status = json.optString("status", "unknown")
            )
        }
    }

    private fun parseItems(raw: JSONArray): List<EventItem> {
        val out = mutableListOf<EventItem>()
        for (i in 0 until raw.length()) {
            val obj = raw.optJSONObject(i) ?: continue
            val payload = obj.optJSONObject("payload") ?: JSONObject()
            val payloadMap = mutableMapOf<String, Any?>()
            payload.keys().forEach { key -> payloadMap[key] = payload.opt(key) }

            out += EventItem(
                event_id = obj.optString("event_id", ""),
                ts = obj.optString("ts", ""),
                source = obj.optString("source", ""),
                type = obj.optString("type", ""),
                payload = payloadMap
            )
        }
        return out
    }

    private fun parseAuthSession(json: JSONObject): AuthSessionResponse {
        return AuthSessionResponse(
            ok = json.optBoolean("ok", false),
            workspace_id = json.optString("workspace_id", ""),
            access_token = json.optString("access_token", ""),
            refresh_token = json.optString("refresh_token", ""),
            access_expires_at = json.optString("access_expires_at", "").ifBlank { null },
            refresh_expires_at = json.optString("refresh_expires_at", "").ifBlank { null }
        )
    }

    private inline fun <T> HttpURLConnection.useResponse(block: (String) -> T): T {
        val code = responseCode
        val stream = if (code in 200..299) inputStream else (errorStream ?: inputStream)
        val body = BufferedReader(stream.reader(Charsets.UTF_8)).use { it.readText() }
        if (code !in 200..299) {
            throw IllegalStateException("HTTP $code: $body")
        }
        return block(body)
    }
}
