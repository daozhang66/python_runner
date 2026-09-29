package com.daozhang.py

internal object McpOverlayGeometry {
    fun recessedTranslation(edge: Int, left: Int, right: Int, size: Int): Float {
        require(size > 0 && right >= left)
        return if (edge == left) -size / 2f else size / 2f
    }

    fun correctedOffset(requested: Int, actual: Int, target: Int): Int =
        (requested.toLong() + target - actual)
            .coerceIn(Int.MIN_VALUE.toLong(), Int.MAX_VALUE.toLong()).toInt()

    fun nearestEdge(x: Int, left: Int, right: Int): Int {
        require(right >= left)
        val clamped = x.coerceIn(left, right)
        return if (clamped.toLong() - left <= right.toLong() - clamped) left else right
    }
}
