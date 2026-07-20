package com.nonto.nonto

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AliyunPushDisplayDecisionTest {
    @Test
    fun sdkFalseReturnsFalseWithoutExtractingOrClaiming() {
        var extractionCount = 0
        var claimCount = 0

        val result = shouldDisplayAliyunPush(
            sdkWouldDisplay = false,
            extractDedupeKey = {
                extractionCount++
                "message:123"
            },
            claim = {
                claimCount++
                true
            }
        )

        assertFalse(result)
        assertEquals(0, extractionCount)
        assertEquals(0, claimCount)
    }

    @Test
    fun missingKeyReturnsTrueWithoutClaiming() {
        var extractionCount = 0
        var claimCount = 0

        val result = shouldDisplayAliyunPush(
            sdkWouldDisplay = true,
            extractDedupeKey = {
                extractionCount++
                null
            },
            claim = {
                claimCount++
                false
            }
        )

        assertTrue(result)
        assertEquals(1, extractionCount)
        assertEquals(0, claimCount)
    }

    @Test
    fun extractionExceptionReturnsTrueWithoutClaiming() {
        var extractionCount = 0
        var claimCount = 0

        val result = shouldDisplayAliyunPush(
            sdkWouldDisplay = true,
            extractDedupeKey = {
                extractionCount++
                throw IllegalStateException("parse failed")
            },
            claim = {
                claimCount++
                false
            }
        )

        assertTrue(result)
        assertEquals(1, extractionCount)
        assertEquals(0, claimCount)
    }

    @Test
    fun successfulClaimReturnsTrueAndReceivesExactRawKey() {
        var extractionCount = 0
        val claimedKeys = mutableListOf<String>()

        val result = shouldDisplayAliyunPush(
            sdkWouldDisplay = true,
            extractDedupeKey = {
                extractionCount++
                " message:123 "
            },
            claim = { key ->
                claimedKeys += key
                true
            }
        )

        assertTrue(result)
        assertEquals(1, extractionCount)
        assertEquals(listOf(" message:123 "), claimedKeys)
    }

    @Test
    fun duplicateClaimReturnsFalse() {
        var extractionCount = 0
        var claimCount = 0

        val result = shouldDisplayAliyunPush(
            sdkWouldDisplay = true,
            extractDedupeKey = {
                extractionCount++
                "message:123"
            },
            claim = {
                claimCount++
                false
            }
        )

        assertFalse(result)
        assertEquals(1, extractionCount)
        assertEquals(1, claimCount)
    }

    @Test
    fun claimExceptionReturnsTrue() {
        var extractionCount = 0
        var claimCount = 0

        val result = shouldDisplayAliyunPush(
            sdkWouldDisplay = true,
            extractDedupeKey = {
                extractionCount++
                "message:123"
            },
            claim = {
                claimCount++
                throw IllegalStateException("storage failed")
            }
        )

        assertTrue(result)
        assertEquals(1, extractionCount)
        assertEquals(1, claimCount)
    }
}
