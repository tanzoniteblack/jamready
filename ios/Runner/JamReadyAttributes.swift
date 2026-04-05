//
//  JamReadyAttributes.swift
//  Runner
//
//  Created by Ryan Smith on 4/5/26.
//

#if os(iOS)
import ActivityKit
import Foundation

struct JamReadyAttributes: ActivityAttributes {
    // MARK: - Dynamic State
    public struct ContentState: Codable, Hashable {
        // Period clock (always a countdown; always displayed white)
        var periodTimeMs: Int
        /// Unix seconds when period hits 0; 0 if stopped.
        var periodEndTimestamp: Double
        var periodRunning: Bool
        var periodNumber: Int

        // Secondary clock — Jam (countdown), Lineup/Timeout (countup), or Intermission (countdown).
        var secTimeMs: Int
        /// Countdown clocks: Unix seconds when clock hits 0.
        /// Countup clocks: Unix seconds when clock was at 0 (start time).
        var secTimestamp: Double
        var secRunning: Bool
        var secCountsDown: Bool
        /// Duration cap for countup clocks (ms); 0 for countdown clocks (unused).
        /// Used by the widget to compute color levels dynamically from timestamps.
        var secDuration: Int
        /// Short label shown in the pill: "J", "L", "T", "I".
        var secLabel: String

        /// Current game phase: "JAM", "LINEUP", "TIMEOUT", "OFFICIAL REVIEW", "INTERMISSION".
        var phaseLabel: String
    }

    // MARK: - Static Attributes
    var team1Name: String
    var team2Name: String
}
#endif
