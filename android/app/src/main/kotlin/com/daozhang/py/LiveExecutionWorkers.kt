package com.daozhang.py

/**
 * Process-wide execution lifetimes survive timeout UI state and Activity replacement. Never drop a
 * worker from a finally block just before it exits: Thread.State.TERMINATED / Process.isAlive are
 * the actual release condition.
 */
internal object LiveExecutionWorkers {
    private val workers = mutableSetOf<Thread>()
    private val processes = mutableSetOf<Process>()

    @Synchronized
    fun start(worker: Thread) {
        prune()
        workers.add(worker)
        try {
            worker.start()
        } catch (error: Throwable) {
            workers.remove(worker)
            throw error
        }
    }

    @Synchronized
    fun track(process: Process) {
        prune()
        processes.add(process)
    }

    @Synchronized
    fun hasActive(): Boolean {
        prune()
        return workers.isNotEmpty() || processes.isNotEmpty()
    }

    private fun prune() {
        workers.removeAll { it.state == Thread.State.TERMINATED }
        processes.removeAll { !it.isAlive }
    }
}
