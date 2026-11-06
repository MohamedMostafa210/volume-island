import Darwin
import QuartzCore
import UIKit

/// Hidden speed meter. Off by default.
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
    private static var deliveryMs: Double = 0
    private static var oursDownMs: Double = 0
    private static var insertMs: Double = 0
    private static var workMs: Double = 0
    private static var taps = 0
    private static var typed = 0
    private static var insertSamples: [Sample] = []
    private static var workSamples: [Sample] = []
    private static var dropSamples: [Sample] = []
    private static var lastRefresh: TimeInterval = 0
    private static var refreshQueued = false
    private static let frames = FrameMonitor()

    static func now() -> TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }

    /// Clears the counters (when the meter is switched on).
    static func reset() {
        taps = 0
        typed = 0
        insertSamples.removeAll()
        workSamples.removeAll()
        dropSamples.removeAll()
    }

    // MARK: Recording

    /// Keyboard launch: object created -> on screen.
    static func markLaunch(since start: TimeInterval) {
        launchMs = (now() - start) * 1000
        refresh(force: true)
    }

    /// Finger lands. "iOS" = until our code got the touch. "ours" = our touch-down work.
    static func recordDown(eventTime: TimeInterval, handlerStart: TimeInterval) {
        guard enabled else { return }
        deliveryMs = (handlerStart - eventTime) * 1000
        oursDownMs = (now() - handlerStart) * 1000
        refresh()
    }

    static func countTap() {
        guard enabled else { return }
        taps += 1
    }

    /// A space touch that became a cursor swipe was not meant to type.
    static func uncountTap() {
        guard enabled else { return }
        taps -= 1
    }

    static func countTyped() {
        guard enabled else { return }
        typed += 1
    }

    /// Finger lifts -> letter handed to the text field.
    static func recordInsert() {
        guard enabled else { return }
        let t = now()
        insertMs = (t - eventTime) * 1000
        insertSamples.append(Sample(time: t, value: insertMs))
    }

    /// How long our code worked on one key (insert, suggestions, redraw).
    static func recordWork(since start: TimeInterval) {
        guard enabled else { return }
        let t = now()
        workMs = (t - start) * 1000
        workSamples.append(Sample(time: t, value: workMs))
        refresh()
    }

    // MARK: Frame counter

    static func startFrames() {
        guard enabled else { return }
        frames.onDrop = { missed in
            dropSamples.append(Sample(time: now(), value: Double(missed)))
        }
        frames.start()
    }

    static func stopFrames() {
        frames.stop()
    }

    // MARK: Display

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
        let worstInsert = recentMax(&insertSamples, at: t)
        let worstWork = recentMax(&workSamples, at: t)
        dropSamples.removeAll { t - $0.time > 30 }
        let lost = Int(dropSamples.reduce(0) { $0 + $1.value })
        box.text = String(
            format: "launch %.0f ms  mem %.1f MB  lost frames %d\ntouch: iOS %.1f + ours %.1f ms  taps %d typed %d\nlift>text %.1f (worst %.1f)  our work %.1f (worst %.1f)",
            launchMs, memoryMB(), lost, deliveryMs, oursDownMs, taps, typed,
            insertMs, worstInsert, workMs, worstWork
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

/// Counts screen frames that were skipped (only runs while the speed meter is on).
private final class FrameMonitor: NSObject {
    private var link: CADisplayLink?
    private var last: CFTimeInterval = 0
    var onDrop: ((Int) -> Void)?

    func start() {
        guard link == nil else { return }
        let newLink = CADisplayLink(target: self, selector: #selector(tick(_:)))
        newLink.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        newLink.add(to: .main, forMode: .common)
        link = newLink
        last = 0
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        let frame = link.targetTimestamp - link.timestamp
        if last > 0, frame > 0 {
            let gap = link.timestamp - last
            let missed = Int((gap / frame).rounded()) - 1
            if missed > 0 { onDrop?(missed) }
        }
        last = link.timestamp
    }
}
