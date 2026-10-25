package com.example.health_ai_app.cv

import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** Dependency-free JVM regression checks, run with the installed Kotlin compiler. */
object WorkoutReplayFrameGateTest {
    @JvmStatic
    fun main(args: Array<String>) {
        check(WorkoutReplayFrameGate.captureMatchesHeldFrame(120_000, 120_000, 120_000_000))
        check(!WorkoutReplayFrameGate.captureMatchesHeldFrame(null, 120_000, 120_000_000))
        check(!WorkoutReplayFrameGate.captureMatchesHeldFrame(20_000, 120_000, 20_000_000))
        check(!WorkoutReplayFrameGate.captureMatchesHeldFrame(120_000, 120_000, 220_000_000))
        // A restarted Surface can still report 16.32s before bitmap latch. Only
        // the post-latch PTS mapped to the NEW session's held frame is accepted.
        check(WorkoutReplayFrameGate.captureMatchesHeldFrame(20_000, 20_000, 20_000_000))
        val gate = WorkoutReplayFrameGate(7)
        gate.begin(100, "clear")
        check(!gate.acknowledge(6, 100, "clear"))
        check(!gate.acknowledge(7, 200, "clear"))
        check(!gate.acknowledge(7, 100, "pose"))
        check(!gate.await(100, "clear", 10)) // Bounded timeout, never advance without ack.
        check(gate.acknowledge(7, 100, "clear"))
        check(!gate.acknowledge(7, 100, "clear"))
        check(gate.await(100, "clear", 10))
        gate.begin(100, "pose")
        check(!gate.acknowledge(7, 100, "clear"))
        check(!gate.await(100, "pose", 10)) // Clearing old pose cannot release inference wait.
        check(gate.acknowledge(7, 100, "pose"))
        check(gate.await(100, "pose", 10))
        gate.begin(200, "clear")
        check(!gate.acknowledge(7, 100, "pose"))

        val finished = CountDownLatch(1)
        val worker = Thread {
            check(!gate.await(200, "clear", 1000))
            finished.countDown()
        }
        worker.start()
        gate.cancel()
        check(finished.await(1, TimeUnit.SECONDS)) // Exit wakes blocked decode.
        worker.join(1000)
        check(!worker.isAlive)
        check(!gate.acknowledge(7, 200, "clear"))
        val restarted = WorkoutReplayFrameGate(8)
        restarted.begin(100, "clear")
        check(!restarted.acknowledge(7, 100, "clear"))
        check(restarted.acknowledge(8, 100, "clear"))
        check(restarted.await(100, "clear", 10))
        println("PASS: exact PTS/phase/generation, timeout, duplicate/stale ack, cancellation and restart")
    }
}
