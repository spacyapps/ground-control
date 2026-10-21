// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (c) 2026 Walter Mak

import Foundation
import IOKit.ps

/// What the Mac is doing, for `MotionPolicy`. Two readings, both local: how busy
/// the processors are, and how the power is.
enum SystemLoad {
    /// Fraction of processor time spent working since the last call, 0…1.
    ///
    /// The whole machine, not this app: the app's own share is what animation
    /// adds, and judging by it would pause the motion because of the motion.
    final class CPUMeter {
        private var previous: host_cpu_load_info?

        /// Nil on the first call (nothing to compare with) or if the kernel
        /// will not say.
        func busyFraction() -> Double? {
            var info = host_cpu_load_info()
            var count = mach_msg_type_number_t(
                MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size
            )
            let status = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                    host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
                }
            }
            guard status == KERN_SUCCESS else { return nil }
            defer { previous = info }
            guard let previous else { return nil }

            // Cumulative ticks per state: user, system, idle, nice.
            func ticks(_ info: host_cpu_load_info, _ slot: Int32) -> Double {
                Double(withUnsafeBytes(of: info.cpu_ticks) {
                    $0.load(fromByteOffset: Int(slot) * MemoryLayout<UInt32>.size, as: UInt32.self)
                })
            }
            let idle = ticks(info, CPU_STATE_IDLE) - ticks(previous, CPU_STATE_IDLE)
            let total = [CPU_STATE_USER, CPU_STATE_SYSTEM, CPU_STATE_IDLE, CPU_STATE_NICE]
                .reduce(0.0) { $0 + ticks(info, $1) - ticks(previous, $1) }
            guard total > 0 else { return nil }
            return min(1, max(0, 1 - idle / total))
        }
    }

    struct Power: Equatable {
        var lowPowerMode: Bool
        var onBattery: Bool
        /// Charge, 0…100, when there is a battery to read.
        var percent: Int?

        /// Low enough to stop spending it on decoration: the Mac's own Low Power
        /// Mode, or running on the battery at or below a fifth.
        static let lowBatteryPercent = 20

        var isLow: Bool {
            lowPowerMode || (onBattery && (percent ?? 100) <= Self.lowBatteryPercent)
        }
    }

    static func power() -> Power {
        var power = Power(lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled, onBattery: false)
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return power }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?
                .takeUnretainedValue() as? [String: Any] else { continue }
            // A desktop has no internal battery; only that one counts.
            guard description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            power.onBattery = description[kIOPSPowerSourceStateKey] as? String == kIOPSBatteryPowerValue
            if let current = description[kIOPSCurrentCapacityKey] as? Int,
               let maximum = description[kIOPSMaxCapacityKey] as? Int, maximum > 0 {
                power.percent = current * 100 / maximum
            }
        }
        return power
    }
}
