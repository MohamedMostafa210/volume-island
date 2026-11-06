import Darwin
import UIKit

/// Hidden speed meter. Off by default. Turn it on or off by holding the
/// clipboard button (left end of the suggestion bar) for about 1.2 seconds.
/// When off, every function here returns after a single true/false check.
enum Perf {
    static var enabled: Bool = UserDefaults.standard.bool(forKey: "nk.debug")
    static weak var label: UILabel?

    /// Time of the touch event that is currently being handled.
    static var eventTime: TimeInterval = 0

    private struct Sample {
        let time: TimeInterval
        let value: Double
    }

    private static var launchMs: Double = 0
    private static var downMs: Double = 0
    private static var insertMs: Double = 0
    private static var workMs: Double = 0
    private static var insertSamples: [Sample] = []
    private static var workSamples: [Sample] = []
    private static var lastRefresh: TimeInterval = 0
    private static var refreshQueued = false

    static func now() -> TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }

    /// Keyboard launch: object created -> on screen.
    static func markLaunch(since start: TimeInterval) {
        launchMs = (now() - start) * 1000
        refresh(force: true)
    }

    /// Finger lands -> key highlight and popup code finished.
    static func recordDown(eventTime: TimeInterval) {
        guard enabled else { return }
        downMs = (now() - eventTime) * 1000
        refresh()
    }

    /// Finger lifts -> letter handed to the text field.
    static func recordInsert() {
        guard enabled else { return }
        let t = now()
        insertMs = (t - eventTime) * 1000
        insertSamples.append(Sample(time: t, value: insertMs))
    }

    /// Finger lifts -> everything (insert, suggestions, redraw) finished.
    static func recordWork(since start: TimeInterval) {
        guard enabled else { return }
        let t = now()
        workMs = (t - start) * 1000
        workSamples.append(Sample(time: t, value: (t - eventTime) * 1000))
        refresh()
    }

    static func refresh(force: Bool = false) {
        guard enabled, let box = label else { return }
        let t = now()
        if !force && t - lastRefresh < 0.25 {
            if !refreshQueued {
                refreshQueued = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    refreshQueued = false
                    refresh(force: true)
                }
            }
            return
        }
        lastRefresh = t
        let slowInsert = recentMax(&insertSamples, at: t)
        let slowTotal = recentMax(&workSamples, at: t)
        box.text = String(
            format: "launch %.0f ms   memory %.1f MB\ntap>popup %.1f   lift>text %.1f (slowest %.1f)\nlift>all done %.1f (slowest %.1f)   ms, last 30s",
            launchMs, memoryMB(), downMs, insertMs, slowInsert, workMs, slowTotal
        )
    }

    private static func recentMax(_ samples: inout [Sample], at t: TimeInterval) -> Double {
        samples.removeAll { t - $0.time > 30 }
        return samples.map { $0.value }.max() ?? 0
    }

    /// Memory the system counts against the keyboard (the number iOS uses to kill it).
    static func memoryMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return Double(info.phys_footprint) / 1_048_576
    }
}
