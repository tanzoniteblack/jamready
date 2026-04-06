//
//  JamReadyWidget.swift
//  JamReadyWidget
//
//  Created by Ryan Smith on 4/5/26.
//

import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - Shared Attributes (must match Runner/JamReadyAttributes.swift)

struct JamReadyAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Period clock (always a countdown; always displayed white)
        var periodTimeMs: Int
        var periodEndTimestamp: Double
        var periodRunning: Bool
        var periodNumber: Int

        // Secondary clock — Jam (countdown), Lineup/Timeout (countup), or Intermission (countdown).
        var secTimeMs: Int
        var secTimestamp: Double
        var secRunning: Bool
        var secCountsDown: Bool
        /// Duration cap for countup clocks (ms); 0 for countdown clocks (unused).
        var secDuration: Int
        var secLabel: String

        var phaseLabel: String
    }

    var team1Name: String
    var team2Name: String
}

// MARK: - Colour Palette
// Matches Flutter Material colours used by _determineAlertColor.

private extension Color {
    static let appBackground     = Color(red: 14/255,  green: 15/255,  blue: 18/255)
    static let clockHealthy      = Color(red: 0.400,  green: 0.733,  blue: 0.416) // green.shade400
    static let clockAmber        = Color(red: 1.000,  green: 0.702,  blue: 0.000) // amber.shade700
    static let clockOrange       = Color(red: 0.937,  green: 0.424,  blue: 0.000) // orange.shade800
    static let clockRed          = Color(red: 0.957,  green: 0.263,  blue: 0.212) // red
    static let clockIntermission = Color(red: 1.000,  green: 0.596,  blue: 0.000) // orange (intermission)
}

private func alertColor(level: Int, phase: String) -> Color {
    if phase == "INTERMISSION" { return .clockIntermission }
    switch level {
    case 1:  return .clockAmber
    case 2:  return .clockOrange
    case 3:  return .clockRed
    default: return .clockHealthy
    }
}

// MARK: - Dynamic Color Level (recomputed each render via TimelineView)

private func computeSecColorLevel(s: JamReadyAttributes.ContentState, now: Date) -> Int {
    guard s.secRunning else { return 0 }
    let nowS = now.timeIntervalSince1970
    if s.secCountsDown {
        let remainingMs = (s.secTimestamp - nowS) * 1000
        if remainingMs <= 0     { return 3 }
        if remainingMs <= 5000  { return 2 }
        if remainingMs <= 10000 { return 1 }
        return 0
    } else {
        guard s.secDuration > 0 else { return 0 }  // unbounded clock (e.g. official timeout)
        let elapsedMs = (nowS - s.secTimestamp) * 1000
        let duration  = Double(s.secDuration)
        if elapsedMs >= duration           { return 3 }
        if elapsedMs >= duration - 5000    { return 2 }
        if elapsedMs >= duration - 10000   { return 1 }
        return 0
    }
}

// MARK: - Helpers

private func formatTime(_ ms: Int) -> String {
    let totalSeconds = Int(ceil(Double(max(ms, 0)) / 1000.0))
    return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
}

// MARK: - ClockText
// Auto-counts down or up using system timestamps when running;
// falls back to a static formatted string when stopped.

private struct ClockText: View {
    let timeMs: Int
    let timestamp: Double   // end time (countdown) or start time (countup)
    let running: Bool
    let countsDown: Bool
    let font: Font
    let color: Color

    var body: some View {
        Group {
            Text("00:00")
                .hidden()
                .overlay(alignment: .leading) {
                    if running {
                        if countsDown {
                            let endDate = Date(timeIntervalSince1970: timestamp)
                            if endDate > Date() {
                                Text(timerInterval: Date()...endDate, countsDown: true)
                            } else {
                                Text("0:00")
                            }
                        } else {
                            // Countup — use start timestamp as the lower bound.
                            let startDate = Date(timeIntervalSince1970: timestamp)
                            let stopDate  = Date(timeIntervalSince1970: timestamp + 3600)
                            Text(timerInterval: startDate...stopDate, countsDown: false)
                        }
                    } else {
                        Text(formatTime(timeMs))
                    }
            }
        }
        .font(font)
        .dynamicTypeSize(.large)
        .monospacedDigit()
        .foregroundStyle(color)
    }
}

// MARK: - Lock Screen / StandBy View

struct LockScreenLiveActivityView: View {
    let context: ActivityViewContext<JamReadyAttributes>

    private var s: JamReadyAttributes.ContentState { context.state }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { tl in
            let secColor = alertColor(level: computeSecColorLevel(s: s, now: tl.date), phase: s.phaseLabel)

            VStack(spacing: 10) {
                Text(s.phaseLabel)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .tracking(3)
                    .foregroundStyle(secColor)

                HStack(spacing: 0) {
                    clockColumn(
                        prefix: "P\(s.periodNumber > 0 ? "\(s.periodNumber)" : "")",
                        timeMs: s.periodTimeMs,
                        timestamp: s.periodEndTimestamp,
                        running: s.periodRunning,
                        countsDown: true,
                        color: .primary,
                        fontSize: 38
                    )

                    Rectangle()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 1, height: 50)

                    clockColumn(
                        prefix: s.secLabel,
                        timeMs: s.secTimeMs,
                        timestamp: s.secTimestamp,
                        running: s.secRunning,
                        countsDown: s.secCountsDown,
                        color: secColor,
                        fontSize: 38
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func clockColumn(
        prefix: String, timeMs: Int, timestamp: Double,
        running: Bool, countsDown: Bool, color: Color, fontSize: CGFloat
    ) -> some View {
        VStack(spacing: 2) {
            Text(prefix)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(1)
                .foregroundStyle(color.opacity(0.7))
            ClockText(
                timeMs: timeMs, timestamp: timestamp,
                running: running, countsDown: countsDown,
                font: .system(size: fontSize, weight: .heavy, design: .monospaced),
                color: color
            )
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Dynamic Island Expanded View

struct DynamicIslandExpandedContent: View {
    let context: ActivityViewContext<JamReadyAttributes>

    private var s: JamReadyAttributes.ContentState { context.state }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { tl in
            let secColor = alertColor(level: computeSecColorLevel(s: s, now: tl.date), phase: s.phaseLabel)
            VStack {
                Text(s.phaseLabel)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(secColor.opacity(0.6))
                    .multilineTextAlignment(.center)
                
                HStack(spacing: 0) {
                    clockColumn("P\(s.periodNumber > 0 ? "\(s.periodNumber)" : "")",
                                timeMs: s.periodTimeMs, timestamp: s.periodEndTimestamp,
                                running: s.periodRunning, countsDown: true, color: .white)
                                    
                    Spacer()

                    clockColumn(s.secLabel,
                                timeMs: s.secTimeMs, timestamp: s.secTimestamp,
                                running: s.secRunning, countsDown: s.secCountsDown, color: secColor)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
            }
        }
    }

    @ViewBuilder
    private func clockColumn(
        _ prefix: String, timeMs: Int, timestamp: Double,
        running: Bool, countsDown: Bool, color: Color
    ) -> some View {
        HStack(alignment: .center, spacing: 5) {
            Text(prefix)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(color.opacity(0.7))
            ClockText(
                timeMs: timeMs, timestamp: timestamp,
                running: running, countsDown: countsDown,
                font: .system(size: 24, weight: .heavy, design: .monospaced),
                color: color
            )
        }
        //.frame(maxWidth: .infinity)
    }
}

// MARK: - Live Activity Widget

struct JamReadyLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: JamReadyAttributes.self) { context in
            LockScreenLiveActivityView(context: context)
                .activityBackgroundTint(Color.appBackground)
        } dynamicIsland: { context in
            let s = context.state

            return DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    DynamicIslandExpandedContent(context: context)
                }
            } compactLeading: {
                HStack(spacing: 2) {
                    Text("P")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.9))
                    ClockText(
                        timeMs: s.periodTimeMs, timestamp: s.periodEndTimestamp,
                        running: s.periodRunning, countsDown: true,
                        font: .system(size: 16, weight: .heavy, design: .monospaced),
                        color: .white
                    )
                }
            } compactTrailing: {
                TimelineView(.periodic(from: .now, by: 1.0)) { tl in
                    let secColor = alertColor(level: computeSecColorLevel(s: s, now: tl.date), phase: s.phaseLabel)
                    HStack(spacing: 2) {
                        Text(s.secLabel)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(secColor.opacity(0.9))
                        ClockText(
                            timeMs: s.secTimeMs, timestamp: s.secTimestamp,
                            running: s.secRunning, countsDown: s.secCountsDown,
                            font: .system(size: 16, weight: .heavy, design: .monospaced),
                            color: secColor
                        )
                    }
                }
            } minimal: {
                TimelineView(.periodic(from: .now, by: 1.0)) { tl in
                    let secColor = alertColor(level: computeSecColorLevel(s: s, now: tl.date), phase: s.phaseLabel)
                        ClockText(
                            timeMs: s.secRunning ? s.secTimeMs : s.periodTimeMs,
                            timestamp: s.secRunning ? s.secTimestamp : s.periodEndTimestamp,
                            running: s.secRunning || s.periodRunning,
                            countsDown: s.secRunning ? s.secCountsDown : true,
                            font: .system(size: 11, weight: .heavy, design: .monospaced),
                            color: s.secRunning ? secColor : .white
                        )
                    }
            }
        }
    }
}

// MARK: - Preview Sample States

private extension JamReadyAttributes {
    static let preview = JamReadyAttributes(team1Name: "Whip It", team2Name: "Derby Dames")
}

private extension JamReadyAttributes.ContentState {
    static let now = Date().timeIntervalSince1970

    /// JAM — 8 s left on jam (amber), period running at 2:05
    static let jam = JamReadyAttributes.ContentState(
        periodTimeMs: 125_000,
        periodEndTimestamp: now + 125,
        periodRunning: true,
        periodNumber: 1,
        secTimeMs: 8_000,
        secTimestamp: now + 8,
        secRunning: true,
        secCountsDown: true,
        secDuration: 0,
        secLabel: "J",
        phaseLabel: "JAM"
    )

    /// LINEUP — 22 s elapsed of a 30 s lineup (orange warning), period stopped
    static let lineup = JamReadyAttributes.ContentState(
        periodTimeMs: 90_000,
        periodEndTimestamp: 0,
        periodRunning: false,
        periodNumber: 1,
        secTimeMs: 22_000,
        secTimestamp: now - 22,
        secRunning: true,
        secCountsDown: false,
        secDuration: 30_000,
        secLabel: "L",
        phaseLabel: "LINEUP"
    )

    /// TIMEOUT — 52 s elapsed (past amber, approaching red)
    static let timeout = JamReadyAttributes.ContentState(
        periodTimeMs: 90_000,
        periodEndTimestamp: 0,
        periodRunning: false,
        periodNumber: 1,
        secTimeMs: 52_000,
        secTimestamp: now - 52,
        secRunning: true,
        secCountsDown: false,
        secDuration: 60_000,
        secLabel: "T",
        phaseLabel: "TIMEOUT"
    )

    /// OFFICIAL REVIEW — unbounded timeout (no color warnings), 90 s elapsed
    static let officialReview = JamReadyAttributes.ContentState(
        periodTimeMs: 90_000,
        periodEndTimestamp: 0,
        periodRunning: false,
        periodNumber: 2,
        secTimeMs: 90_000,
        secTimestamp: now - 90,
        secRunning: true,
        secCountsDown: false,
        secDuration: 0,
        secLabel: "T",
        phaseLabel: "OFFICIAL REVIEW"
    )

    /// INTERMISSION — 5 min remaining
    static let intermission = JamReadyAttributes.ContentState(
        periodTimeMs: 0,
        periodEndTimestamp: 0,
        periodRunning: false,
        periodNumber: 1,
        secTimeMs: 300_000,
        secTimestamp: now + 300,
        secRunning: true,
        secCountsDown: true,
        secDuration: 0,
        secLabel: "I",
        phaseLabel: "INTERMISSION"
    )
}

// MARK: - Previews

#Preview("Lock Screen", as: .content, using: JamReadyAttributes.preview) {
    JamReadyLiveActivity()
} contentStates: {
    JamReadyAttributes.ContentState.jam
    JamReadyAttributes.ContentState.lineup
    JamReadyAttributes.ContentState.timeout
    JamReadyAttributes.ContentState.officialReview
    JamReadyAttributes.ContentState.intermission
}

#Preview("Dynamic Island — Compact", as: .dynamicIsland(.compact), using: JamReadyAttributes.preview) {
    JamReadyLiveActivity()
} contentStates: {
    JamReadyAttributes.ContentState.jam
    JamReadyAttributes.ContentState.lineup
    JamReadyAttributes.ContentState.timeout
    JamReadyAttributes.ContentState.officialReview
    JamReadyAttributes.ContentState.intermission
}

#Preview("Dynamic Island — Expanded", as: .dynamicIsland(.expanded), using: JamReadyAttributes.preview) {
    JamReadyLiveActivity()
} contentStates: {
    JamReadyAttributes.ContentState.jam
    JamReadyAttributes.ContentState.lineup
    JamReadyAttributes.ContentState.timeout
    JamReadyAttributes.ContentState.officialReview
    JamReadyAttributes.ContentState.intermission
}

#Preview("Dynamic Island — Minimal", as: .dynamicIsland(.minimal), using: JamReadyAttributes.preview) {
    JamReadyLiveActivity()
} contentStates: {
    JamReadyAttributes.ContentState.jam
    JamReadyAttributes.ContentState.lineup
    JamReadyAttributes.ContentState.timeout
    JamReadyAttributes.ContentState.officialReview
    JamReadyAttributes.ContentState.intermission
}
