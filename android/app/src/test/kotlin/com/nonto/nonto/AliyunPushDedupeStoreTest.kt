package com.nonto.nonto

import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.Future
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AliyunPushDedupeStoreTest {
    private val sevenDaysMillis = 7L * 24 * 60 * 60 * 1000

    @Test
    fun firstValidClaimReturnsTrueAndPersistsOnlyKeyAndTimestamp() {
        val storage = FakeStorage()
        val store = store(storage, now = 1_000L)

        assertTrue(store.claim("message:12345"))

        assertEquals(mapOf("message:12345" to 1_000L), storage.claims)
        assertEquals(1, storage.writeCount)
    }

    @Test
    fun sameStoreDuplicateReturnsFalse() {
        val storage = FakeStorage()
        val store = store(storage, now = 1_000L)

        assertTrue(store.claim("message:12345"))
        assertFalse(store.claim("message:12345"))
        assertEquals(1, storage.writeCount)
    }

    @Test
    fun recreatedStoreOverSameStorageRejectsDuplicate() {
        val storage = FakeStorage()

        assertTrue(store(storage, now = 1_000L).claim("message:12345"))
        assertFalse(store(storage, now = 2_000L).claim("message:12345"))
    }

    @Test
    fun acceptsCanonicalMessageAndNotificationKeys() {
        val storage = FakeStorage()
        var now = 1_000L
        val store = AliyunPushDedupeStore(storage, nowMillis = { now++ })

        assertTrue(store.claim("message:AbC_123-xyz.9"))
        assertTrue(store.claim("notification:42"))

        assertEquals(setOf("message:AbC_123-xyz.9", "notification:42"), storage.claims.keys)
    }

    @Test
    fun malformedKeysFailOpenWithoutReadingOrWritingStorage() {
        val storage = FakeStorage()
        val store = store(storage, now = 1_000L)
        val malformedKeys = listOf(
            "",
            " ",
            "message:",
            "message: ",
            "message:two words",
            "message:line\nbreak",
            "message:unsafe/value",
            "notification:",
            "notification:0",
            "notification:-1",
            "notification:+1",
            "notification:01",
            "notification:1 2",
            "unknown:123",
            "message:" + "a".repeat(249)
        )

        malformedKeys.forEach { key -> assertTrue("Expected fail-open for <$key>", store.claim(key)) }

        assertEquals(0, storage.readCount)
        assertEquals(0, storage.writeCount)
        assertTrue(storage.claims.isEmpty())
    }

    @Test
    fun claimAtTtlBoundaryIsExpiredAndPersistsNewTimestamp() {
        val storage = FakeStorage(mutableMapOf("message:12345" to 1_000L))
        val store = store(storage, now = 1_000L + sevenDaysMillis)

        assertTrue(store.claim("message:12345"))

        assertEquals(1_000L + sevenDaysMillis, storage.claims["message:12345"])
        assertEquals(1, storage.writeCount)
    }

    @Test
    fun futureAndCorruptTimestampsArePruned() {
        val storage = FakeStorage(
            mutableMapOf(
                "message:future" to 20_000L,
                "message:negative" to -1L,
                "message:fresh" to 9_500L
            )
        )
        val store = store(storage, now = 10_000L)

        assertTrue(store.claim("notification:7"))

        assertEquals(
            mapOf("message:fresh" to 9_500L, "notification:7" to 10_000L),
            storage.claims
        )
    }

    @Test
    fun storeRetainsNewestEntriesAndEvictsOldest() {
        val storage = FakeStorage()
        var now = 1_000L
        val store = AliyunPushDedupeStore(
            storage = storage,
            nowMillis = { now++ },
            maxEntries = 3
        )

        assertTrue(store.claim("message:one"))
        assertTrue(store.claim("message:two"))
        assertTrue(store.claim("message:three"))
        assertTrue(store.claim("message:four"))

        assertEquals(setOf("message:two", "message:three", "message:four"), storage.claims.keys)
        assertEquals(3, storage.claims.size)
    }

    @Test
    fun equalTimestampEvictionUsesPreferredKeyThenLexicographicKey() {
        val storage = FakeStorage(
            mutableMapOf(
                "message:zulu" to 1_000L,
                "message:alpha" to 1_000L
            )
        )
        val store = AliyunPushDedupeStore(
            storage = storage,
            nowMillis = { 1_000L },
            maxEntries = 2
        )

        assertTrue(store.claim("message:middle"))

        assertEquals(
            linkedMapOf("message:middle" to 1_000L, "message:alpha" to 1_000L),
            storage.claims
        )
    }

    @Test
    fun readExceptionFailsOpenWithoutAttemptingWrite() {
        val storage = FakeStorage().apply { throwOnRead = true }

        assertTrue(store(storage, now = 1_000L).claim("message:12345"))

        assertEquals(1, storage.readCount)
        assertEquals(0, storage.writeCount)
    }

    @Test
    fun writeExceptionFailsOpen() {
        val storage = FakeStorage().apply { throwOnWrite = true }

        assertTrue(store(storage, now = 1_000L).claim("message:12345"))

        assertEquals(1, storage.writeCount)
        assertTrue(storage.claims.isEmpty())
    }

    @Test
    fun recordCodecRoundTripsClaims() {
        val claims = linkedMapOf(
            "message:AbC_123-xyz.9" to 1_000L,
            "notification:42" to 2_000L
        )

        assertEquals(claims, AliyunPushDedupeRecordCodec.decode(AliyunPushDedupeRecordCodec.encode(claims)))
    }

    @Test
    fun recordCodecSkipsInvalidBase64() {
        assertTrue(AliyunPushDedupeRecordCodec.decode(setOf("***:1000")).isEmpty())
    }

    @Test
    fun recordCodecSkipsRecordWithoutSeparator() {
        val encodedRecord = AliyunPushDedupeRecordCodec.encode(mapOf("message:valid" to 1_000L)).single()
        val encodedKey = encodedRecord.substringBefore(':')

        assertTrue(AliyunPushDedupeRecordCodec.decode(setOf(encodedKey)).isEmpty())
    }

    @Test
    fun recordCodecSkipsInvalidAndOverflowTimestamps() {
        val encodedRecord = AliyunPushDedupeRecordCodec.encode(mapOf("message:valid" to 1_000L)).single()
        val encodedKey = encodedRecord.substringBefore(':')

        assertTrue(
            AliyunPushDedupeRecordCodec.decode(
                setOf(
                    "$encodedKey:not-a-number",
                    "$encodedKey:9223372036854775808"
                )
            ).isEmpty()
        )
    }

    @Test
    fun recordCodecChoosesNewestTimestampForDuplicateDecodedKey() {
        val older = AliyunPushDedupeRecordCodec.encode(mapOf("message:duplicate" to 1_000L)).single()
        val newer = AliyunPushDedupeRecordCodec.encode(mapOf("message:duplicate" to 2_000L)).single()

        assertEquals(
            mapOf("message:duplicate" to 2_000L),
            AliyunPushDedupeRecordCodec.decode(linkedSetOf(newer, older))
        )
    }

    @Test
    fun concurrentSameKeyClaimsOnOneStoreAllowExactlyOneWinner() {
        val storage = FakeStorage()
        val store = store(storage, now = 1_000L)
        val workers = 24
        val ready = CountDownLatch(workers)
        val start = CountDownLatch(1)
        val done = CountDownLatch(workers)
        val executor = Executors.newFixedThreadPool(workers)
        val futures = mutableListOf<Future<Boolean>>()

        try {
            repeat(workers) {
                futures += executor.submit<Boolean> {
                    ready.countDown()
                    try {
                        start.await()
                        store.claim("notification:42")
                    } finally {
                        done.countDown()
                    }
                }
            }

            assertTrue(ready.await(5, TimeUnit.SECONDS))
            start.countDown()
            assertTrue(done.await(10, TimeUnit.SECONDS))
            assertEquals(1, futures.count { it.get(10, TimeUnit.SECONDS) })
            assertEquals(mapOf("notification:42" to 1_000L), storage.claims)
            assertEquals(1, storage.writeCount)
        } finally {
            start.countDown()
            executor.shutdownNow()
            executor.awaitTermination(10, TimeUnit.SECONDS)
        }
    }

    @Test
    fun concurrentSameKeyClaimsOnTwoStoresAllowExactlyOneWinner() {
        val storage = FirstReadBlockingStorage()
        val firstStore = store(storage, now = 1_000L)
        val secondStore = store(storage, now = 1_000L)
        val executor = Executors.newFixedThreadPool(2)
        val done = CountDownLatch(2)
        val secondClaimStarted = CountDownLatch(1)
        val futures = mutableListOf<Future<Boolean>>()

        try {
            futures += submitClaim(executor, done, firstStore, "notification:42")
            assertTrue(storage.firstReadCaptured.await(5, TimeUnit.SECONDS))
            futures += submitClaim(
                executor,
                done,
                secondStore,
                "notification:42",
                started = secondClaimStarted
            )
            assertTrue(secondClaimStarted.await(5, TimeUnit.SECONDS))
            storage.secondReadCaptured.await(1, TimeUnit.SECONDS)
            storage.releaseFirstRead.countDown()

            assertTrue(done.await(10, TimeUnit.SECONDS))
            assertEquals(1, futures.count { it.get(10, TimeUnit.SECONDS) })
            assertEquals(mapOf("notification:42" to 1_000L), storage.claims)
        } finally {
            storage.releaseFirstRead.countDown()
            executor.shutdownNow()
            executor.awaitTermination(10, TimeUnit.SECONDS)
        }
    }

    @Test
    fun concurrentDistinctKeyClaimsOnTwoStoresBothSurvive() {
        val storage = FirstReadBlockingStorage()
        val firstStore = store(storage, now = 1_000L)
        val secondStore = store(storage, now = 1_000L)
        val executor = Executors.newFixedThreadPool(2)
        val done = CountDownLatch(2)
        val secondClaimStarted = CountDownLatch(1)
        val futures = mutableListOf<Future<Boolean>>()

        try {
            futures += submitClaim(executor, done, firstStore, "message:first")
            assertTrue(storage.firstReadCaptured.await(5, TimeUnit.SECONDS))
            futures += submitClaim(
                executor,
                done,
                secondStore,
                "message:second",
                started = secondClaimStarted
            )
            assertTrue(secondClaimStarted.await(5, TimeUnit.SECONDS))
            storage.secondReadCaptured.await(1, TimeUnit.SECONDS)
            storage.releaseFirstRead.countDown()

            assertTrue(done.await(10, TimeUnit.SECONDS))
            assertEquals(listOf(true, true), futures.map { it.get(10, TimeUnit.SECONDS) })
            assertEquals(
                mapOf("message:first" to 1_000L, "message:second" to 1_000L),
                storage.claims
            )
        } finally {
            storage.releaseFirstRead.countDown()
            executor.shutdownNow()
            executor.awaitTermination(10, TimeUnit.SECONDS)
        }
    }

    private fun submitClaim(
        executor: java.util.concurrent.ExecutorService,
        done: CountDownLatch,
        store: AliyunPushDedupeStore,
        key: String,
        started: CountDownLatch? = null
    ): Future<Boolean> {
        return executor.submit<Boolean> {
            started?.countDown()
            try {
                store.claim(key)
            } finally {
                done.countDown()
            }
        }
    }

    private fun store(storage: PushDedupeStorage, now: Long): AliyunPushDedupeStore {
        return AliyunPushDedupeStore(storage = storage, nowMillis = { now })
    }

    private class FakeStorage(
        initialClaims: MutableMap<String, Long> = mutableMapOf()
    ) : PushDedupeStorage {
        var claims: MutableMap<String, Long> = initialClaims.toMutableMap()
        var readCount = 0
        var writeCount = 0
        var throwOnRead = false
        var throwOnWrite = false

        override fun readClaims(): Map<String, Long> {
            readCount++
            if (throwOnRead) throw IllegalStateException("read failed")
            return claims.toMap()
        }

        override fun writeClaims(claims: Map<String, Long>) {
            writeCount++
            if (throwOnWrite) throw IllegalStateException("write failed")
            this.claims = claims.toMutableMap()
        }
    }

    private class FirstReadBlockingStorage : PushDedupeStorage {
        val firstReadCaptured = CountDownLatch(1)
        val secondReadCaptured = CountDownLatch(1)
        val releaseFirstRead = CountDownLatch(1)
        private val lock = Any()
        private val readSequence = AtomicInteger()
        private var storedClaims = mutableMapOf<String, Long>()

        val claims: Map<String, Long>
            get() = synchronized(lock) { storedClaims.toMap() }

        override fun readClaims(): Map<String, Long> {
            val snapshot = synchronized(lock) { storedClaims.toMap() }
            when (readSequence.incrementAndGet()) {
                1 -> {
                    firstReadCaptured.countDown()
                    if (!releaseFirstRead.await(10, TimeUnit.SECONDS)) {
                        throw IllegalStateException("Timed out waiting to release first read")
                    }
                }
                2 -> secondReadCaptured.countDown()
            }
            return snapshot
        }

        override fun writeClaims(claims: Map<String, Long>) {
            synchronized(lock) {
                storedClaims = claims.toMutableMap()
            }
        }
    }
}
