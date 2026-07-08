// LocalAIEdgeApp/Services/Tools/DeviceInfoTools.swift
import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// `get_current_time` — current date/time and timezone. Models have no sense of
/// "now" without this; questions like "what day is it?" or "how long until 2027?"
/// become answerable.
struct GetCurrentTimeTool: Tool {
    let name = "get_current_time"

    let definition = ToolDefinition(
        name: "get_current_time",
        summary: "Get the current date, time, day of week, and timezone on the user's device.",
        parameters: [:]
    )

    func run(argsJSON: String, context: ToolContext) async -> ToolResult {
        let now = Date()
        let cal = Calendar.current
        let weekdayIndex = cal.component(.weekday, from: now) - 1
        let symbols = cal.weekdaySymbols
        let weekday = (0..<symbols.count).contains(weekdayIndex) ? symbols[weekdayIndex] : ""
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .long
        formatter.timeZone = .current
        let tz = TimeZone.current.identifier
        let output = """
        Current date and time: \(formatter.string(from: now))
        Day of week: \(weekday)
        Timezone: \(tz) (UTC offset \(TimeZone.current.secondsFromGMT()/3600)h)
        """
        return ToolResult(toolName: name, output: output)
    }
}

/// `get_device_info` — read-only hardware/OS facts about the device. No PII.
/// Lets the model tailor answers to the user's hardware (e.g. memory limits).
struct GetDeviceInfoTool: Tool {
    let name = "get_device_info"

    let definition = ToolDefinition(
        name: "get_device_info",
        summary: "Get read-only facts about the user's device: model name, OS version, chip tier, and (if a model is loaded) its name and runtime. No personal data.",
        parameters: [:]
    )

    func run(argsJSON: String, context: ToolContext) async -> ToolResult {
        var lines: [String] = []

        #if canImport(UIKit)
        let device = UIDevice.current
        lines.append("Device: \(device.model)")
        lines.append("System: \(device.systemName) \(device.systemVersion)")
        #endif

        let machine = DeviceCapabilityService.machineModel()
        if !machine.isEmpty { lines.append("Hardware ID: \(machine)") }

        let tier = DeviceTier.current()
        let budget = String(format: "%.1f", tier.usableWeightGB)
        lines.append("Capability tier: \(tier.displayName) (~\(budget) GB model weight budget)")

        if let model = context.installedModel {
            lines.append("Active model: \(model.catalogItem.displayName) (\(model.catalogItem.runtimeType.rawValue))")
        } else {
            lines.append("Active model: none")
        }

        return ToolResult(toolName: name, output: lines.joined(separator: "\n"))
    }
}

/// `get_battery_level` — battery percentage and charge state. Requires battery
/// monitoring to be enabled; returns a clear "unavailable" message otherwise.
struct GetBatteryLevelTool: Tool {
    let name = "get_battery_level"

    let definition = ToolDefinition(
        name: "get_battery_level",
        summary: "Get the device's current battery level and charging state.",
        parameters: [:]
    )

    func run(argsJSON: String, context: ToolContext) async -> ToolResult {
        #if canImport(UIKit)
        let device = UIDevice.current
        let wasMonitoring = device.isBatteryMonitoringEnabled
        if !wasMonitoring { device.isBatteryMonitoringEnabled = true }
        defer { if !wasMonitoring { device.isBatteryMonitoringEnabled = false } }

        // Battery state needs a runloop tick to populate after enabling; if unknown,
        // surface that honestly rather than a stale value.
        let level = Int((device.batteryLevel * 100).rounded())
        let state: String
        switch device.batteryState {
        case .charging: state = "charging"
        case .unplugged: state = "on battery"
        case .full: state = "full"
        default: state = "unknown"
        }

        if device.batteryState == .unknown {
            return ToolResult(toolName: name, output: "Battery state unavailable on this device.")
        }
        return ToolResult(toolName: name, output: "Battery: \(level)% (\(state)).")
        #else
        return ToolResult(toolName: name, output: "Battery information is only available on iOS.")
        #endif
    }
}
