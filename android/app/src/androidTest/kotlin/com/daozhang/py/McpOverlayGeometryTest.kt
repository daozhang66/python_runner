package com.daozhang.py

import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class McpOverlayGeometryTest {
    @Test
    fun recessedBallLeavesExactlyHalfVisibleOnEitherEdge() {
        for (size in listOf(48, 96, 144)) {
            assertEquals(-size / 2f, McpOverlayGeometry.recessedTranslation(0, 0, 1032, size), 0f)
            assertEquals(size / 2f, McpOverlayGeometry.recessedTranslation(1032, 0, 1032, size), 0f)
            assertEquals(-size / 2f, McpOverlayGeometry.recessedTranslation(40, 40, 950, size), 0f)
        }
    }
    @Test
    fun correctsWindowOffsetsUsingRenderedPosition() {
        assertEquals(-24, McpOverlayGeometry.correctedOffset(0, 24, 0))
        assertEquals(1056, McpOverlayGeometry.correctedOffset(1032, 1008, 1032))
        assertEquals(40, McpOverlayGeometry.correctedOffset(40, 40, 40))
        assertEquals(Int.MAX_VALUE, McpOverlayGeometry.correctedOffset(Int.MAX_VALUE, 0, 100))
    }
    @Test
    fun snapsToNearestEdgeIncludingInsetsAndOvershoot() {
        assertEquals(0, McpOverlayGeometry.nearestEdge(300, 0, 1032))
        assertEquals(1032, McpOverlayGeometry.nearestEdge(800, 0, 1032))
        assertEquals(0, McpOverlayGeometry.nearestEdge(516, 0, 1032))
        assertEquals(40, McpOverlayGeometry.nearestEdge(-100, 40, 950))
        assertEquals(950, McpOverlayGeometry.nearestEdge(2000, 40, 950))
        assertEquals(40, McpOverlayGeometry.nearestEdge(495, 40, 950))
        assertEquals(950, McpOverlayGeometry.nearestEdge(496, 40, 950))
        assertEquals(20, McpOverlayGeometry.nearestEdge(100, 20, 20))
    }
}
