package com.example.health_ai_app.cv

import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** One replay frame may advance only after the matching Flutter frame finishes. */
internal class WorkoutReplayFrameGate(private val sessionGen: Long) {
    companion object {
        fun captureMatchesHeldFrame(capturedPtsUs: Long?, expectedPtsUs: Long, afterNs: Long): Boolean =
            capturedPtsUs != null && capturedPtsUs == expectedPtsUs &&
                kotlin.math.abs(afterNs / 1000L - expectedPtsUs) <= 500L
    }

    private data class Pending(val ptsMs: Long, val phase: String, val latch: CountDownLatch)
    private var pending: Pending? = null
    private var cancelled = false

    @Synchronized
    fun begin(ptsMs: Long, phase: String) {
        check(!cancelled)
        pending = Pending(ptsMs, phase, CountDownLatch(1))
    }

    @Synchronized
    fun acknowledge(generation: Long, ptsMs: Long, phase: String): Boolean {
        val frame = pending ?: return false
        if (cancelled || generation != sessionGen || frame.ptsMs != ptsMs ||
            frame.phase != phase || frame.latch.count == 0L) return false
        frame.latch.countDown()
        return true
    }

    fun await(ptsMs: Long, phase: String, timeoutMs: Long): Boolean {
        val frame = synchronized(this) { pending } ?: return false
        if (frame.ptsMs != ptsMs || frame.phase != phase) return false
        if (!frame.latch.await(timeoutMs, TimeUnit.MILLISECONDS)) return false
        return synchronized(this) { !cancelled && pending === frame }
    }

    @Synchronized
    fun cancel() {
        cancelled = true
        pending?.latch?.countDown()
    }
}
