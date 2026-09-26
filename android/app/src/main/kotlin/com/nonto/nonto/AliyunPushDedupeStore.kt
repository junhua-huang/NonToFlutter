package com.nonto.nonto

import android.content.Context
import android.content.SharedPreferences
import java.nio.charset.StandardCharsets
import java.util.Base64

internal interface PushDedupeStorage {
    fun readClaims(): Map<String, Long>
    fun writeClaims(claims: Map<String, Long>)
}

/**
 * Persistent, process-recreation-safe claim store for Aliyun push identifiers.
 *
 * Canonical keys are at most 256 characters. Message IDs may contain only ASCII
 * letters, digits, '.', '_', and '-'. Notification IDs are canonical positive
 * decimal integers (no sign or leading zeroes).
 */
internal class AliyunPushDedupeStore(
    private val storage: PushDedupeStorage,
    private val nowMillis: () -> Long,
    private val ttlMillis: Long = DEFAULT_TTL_MILLIS,
    private val maxEntries: Int = DEFAULT_MAX_ENTRIES
) {
    init {
        require(ttlMillis > 0) { "ttlMillis must be positive" }
        require(maxEntries > 0) { "maxEntries must be positive" }
    }

    fun claim(key: String): Boolean {
        if (!isCanonicalPushDedupeKey(key)) return true

        // The manifest receiver runs in the app process. This shared lock coordinates all
        // process-local store instances so their complete read/prune/check/write transaction is atomic.
        return synchronized(PROCESS_LOCAL_TRANSACTION_LOCK) {
            try {
                val now = nowMillis()
                val storedClaims = storage.readClaims()
                val activeClaims = retainNewest(
                    storedClaims.filterTo(LinkedHashMap()) { (storedKey, timestamp) ->
                        isCanonicalPushDedupeKey(storedKey) &&
                            timestamp > 0L &&
                            timestamp <= now &&
                            now - timestamp < ttlMillis
                    },
                    maxEntries,
                    preferredKey = key
                )

                if (activeClaims.containsKey(key)) {
                    if (activeClaims != storedClaims) storage.writeClaims(activeClaims)
                    false
                } else {
                    activeClaims[key] = now
                    val boundedClaims = retainNewest(activeClaims, maxEntries, preferredKey = key)
                    storage.writeClaims(boundedClaims)
                    true
                }
            } catch (_: Exception) {
                true
            }
        }
    }

    private fun retainNewest(
        claims: Map<String, Long>,
        limit: Int,
        preferredKey: String
    ): LinkedHashMap<String, Long> {
        if (claims.size <= limit) return LinkedHashMap(claims)

        val newest = claims.entries
            .sortedWith(
                compareByDescending<Map.Entry<String, Long>> { it.value }
                    .thenByDescending { it.key == preferredKey }
                    .thenBy { it.key }
            )
            .take(limit)

        return LinkedHashMap<String, Long>(newest.size).apply {
            newest.forEach { (key, timestamp) -> put(key, timestamp) }
        }
    }

    private companion object {
        val PROCESS_LOCAL_TRANSACTION_LOCK = Any()
        const val DEFAULT_TTL_MILLIS = 7L * 24 * 60 * 60 * 1000
        const val DEFAULT_MAX_ENTRIES = 512
    }
}

internal object AliyunPushDedupeRecordCodec {
    private const val RECORD_SEPARATOR = ':'
    private val encoder = Base64.getUrlEncoder().withoutPadding()
    private val decoder = Base64.getUrlDecoder()

    fun encode(claims: Map<String, Long>): Set<String> {
        return claims.mapTo(LinkedHashSet(claims.size)) { (key, timestamp) ->
            val encodedKey = encoder.encodeToString(key.toByteArray(StandardCharsets.UTF_8))
            "$encodedKey$RECORD_SEPARATOR$timestamp"
        }
    }

    fun decode(records: Set<String>): Map<String, Long> {
        val claims = LinkedHashMap<String, Long>(records.size)

        records.forEach { record ->
            val separator = record.indexOf(RECORD_SEPARATOR)
            if (separator <= 0 || separator == record.lastIndex) return@forEach

            val timestamp = record.substring(separator + 1).toLongOrNull() ?: return@forEach
            val key = try {
                String(decoder.decode(record.substring(0, separator)), StandardCharsets.UTF_8)
            } catch (_: IllegalArgumentException) {
                return@forEach
            }

            if (!isCanonicalPushDedupeKey(key)) return@forEach
            val previous = claims[key]
            if (previous == null || timestamp > previous) claims[key] = timestamp
        }

        return claims
    }
}

internal class SharedPreferencesPushDedupeStorage(context: Context) : PushDedupeStorage {
    private val preferences: SharedPreferences = context.applicationContext.getSharedPreferences(
        PREFERENCE_NAME,
        Context.MODE_PRIVATE
    )

    override fun readClaims(): Map<String, Long> {
        val records = preferences.getStringSet(CLAIMS_KEY, emptySet()).orEmpty()
        return AliyunPushDedupeRecordCodec.decode(records)
    }

    override fun writeClaims(claims: Map<String, Long>) {
        val records = AliyunPushDedupeRecordCodec.encode(claims)

        if (!preferences.edit().putStringSet(CLAIMS_KEY, records).commit()) {
            throw IllegalStateException("Could not durably persist push dedupe claims")
        }
    }

    private companion object {
        const val PREFERENCE_NAME = "com.nonto.nonto.push_dedupe.v1"
        const val CLAIMS_KEY = "claims_v1"
    }
}

internal fun createAliyunPushDedupeStore(
    context: Context,
    nowMillis: () -> Long = System::currentTimeMillis
): AliyunPushDedupeStore {
    return AliyunPushDedupeStore(
        storage = SharedPreferencesPushDedupeStorage(context.applicationContext),
        nowMillis = nowMillis
    )
}

private const val MAX_DEDUPE_KEY_LENGTH = 256
private val SAFE_MESSAGE_ID = Regex("[A-Za-z0-9._-]+")
private val POSITIVE_NOTIFICATION_ID = Regex("[1-9][0-9]*")

private fun isCanonicalPushDedupeKey(key: String): Boolean {
    if (key.isEmpty() || key.length > MAX_DEDUPE_KEY_LENGTH) return false

    return when {
        key.startsWith("message:") -> SAFE_MESSAGE_ID.matches(key.substringAfter("message:"))
        key.startsWith("notification:") ->
            POSITIVE_NOTIFICATION_ID.matches(key.substringAfter("notification:"))
        else -> false
    }
}
