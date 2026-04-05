import Flutter
import UIKit
import ActivityKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {

    /// Persisted across launches so a dirty-shutdown activity can be cleaned up on next start.
    private static let liveActivityIDKey = "com.jamready.liveActivityID"

    private var liveActivityID: String? {
        get { UserDefaults.standard.string(forKey: Self.liveActivityIDKey) }
        set {
            if let id = newValue {
                UserDefaults.standard.set(id, forKey: Self.liveActivityIDKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.liveActivityIDKey)
            }
        }
    }

    /// How long after the last update before the activity is shown as stale.
    /// Acts as a soft TTL; the OS enforces a hard 8-hour maximum.
    private static let activityStaleDuration: TimeInterval = 10 * 60  // 10 minutes

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // Clean up an activity left over from a previous session (crash, power-off, etc.).
        // Uses the persisted ID so we only touch our own activity, and passes nil for content
        // to avoid deserialising a potentially stale ContentState schema.
        if #available(iOS 16.2, *), let storedID = liveActivityID {
            Task {
                if let activity = Activity<JamReadyAttributes>.activities.first(where: { $0.id == storedID }) {
                    await activity.end(nil, dismissalPolicy: .immediate)
                }
                liveActivityID = nil
            }
        }
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    override func applicationWillTerminate(_ application: UIApplication) {
        // Force-close from the app switcher. activity.end() is a local write and
        // completes fast enough that the OS won't kill the process before the Task fires.
        endLiveActivity()
        super.applicationWillTerminate(application)
    }

    func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
        GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
        if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "JamReadyLiveActivity") {
            setupLiveActivityChannel(binaryMessenger: registrar.messenger())
        }
    }

    private func setupLiveActivityChannel(binaryMessenger: FlutterBinaryMessenger) {
        let channel = FlutterMethodChannel(
            name: "com.jamready.app/live_activity",
            binaryMessenger: binaryMessenger
        )
        channel.setMethodCallHandler { [weak self] call, result in
            guard let self else { return }
            let args = call.arguments as? [String: Any] ?? [:]

            switch call.method {
            case "startActivity":
                let id = self.startLiveActivity(args: args)
                result(id)
            case "updateActivity":
                self.updateLiveActivity(args: args)
                result(nil)
            case "endActivity":
                self.endLiveActivity()
                result(nil)
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    // MARK: - ActivityKit Operations

    @discardableResult
    private func startLiveActivity(args: [String: Any]) -> String? {
        guard #available(iOS 16.2, *) else { return nil }

        endLiveActivity()

        let attributes = JamReadyAttributes(
            team1Name: args["team1Name"] as? String ?? "Team 1",
            team2Name: args["team2Name"] as? String ?? "Team 2"
        )
        let content = ActivityContent(
            state: contentState(from: args),
            staleDate: Date(timeIntervalSinceNow: Self.activityStaleDuration)
        )

        do {
            let activity = try Activity<JamReadyAttributes>.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
            liveActivityID = activity.id
            print("[LiveActivity] Started: \(activity.id)")
            return activity.id
        } catch {
            print("[LiveActivity] Failed to start: \(error)")
            return nil
        }
    }

    private func updateLiveActivity(args: [String: Any]) {
        guard #available(iOS 16.2, *) else { return }
        guard let id = liveActivityID else { return }
        guard let activity = Activity<JamReadyAttributes>.activities.first(where: { $0.id == id }) else {
            print("[LiveActivity] Activity \(id) not found for update")
            return
        }

        let content = ActivityContent(
            state: contentState(from: args),
            staleDate: Date(timeIntervalSinceNow: Self.activityStaleDuration)
        )
        Task { await activity.update(content) }
    }

    private func endLiveActivity() {
        guard #available(iOS 16.2, *) else { return }
        guard let id = liveActivityID else { return }
        liveActivityID = nil  // clear before async end so re-entrant calls are no-ops
        if let activity = Activity<JamReadyAttributes>.activities.first(where: { $0.id == id }) {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }

    @available(iOS 16.2, *)
    private func contentState(from args: [String: Any]) -> JamReadyAttributes.ContentState {
        JamReadyAttributes.ContentState(
            periodTimeMs:       args["periodTimeMs"]       as? Int    ?? 0,
            periodEndTimestamp: args["periodEndTimestamp"] as? Double ?? 0.0,
            periodRunning:      args["periodRunning"]      as? Bool   ?? false,
            periodNumber:       args["periodNumber"]       as? Int    ?? 1,
            secTimeMs:          args["secTimeMs"]          as? Int    ?? 0,
            secTimestamp:       args["secTimestamp"]       as? Double ?? 0.0,
            secRunning:         args["secRunning"]         as? Bool   ?? false,
            secCountsDown:      args["secCountsDown"]      as? Bool   ?? true,
            secDuration:        args["secDuration"]        as? Int    ?? 0,
            secLabel:           args["secLabel"]           as? String ?? "J",
            phaseLabel:         args["phaseLabel"]         as? String ?? "LINEUP"
        )
    }
}
