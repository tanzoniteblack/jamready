import Flutter
import UIKit
import ActivityKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {

    private var liveActivityID: String?

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
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
            staleDate: nil
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
            staleDate: nil
        )
        Task { await activity.update(content) }
    }

    private func endLiveActivity() {
        guard #available(iOS 16.2, *) else { return }
        guard let id = liveActivityID else { return }
        if let activity = Activity<JamReadyAttributes>.activities.first(where: { $0.id == id }) {
            Task { await activity.end(ActivityContent(state: activity.content.state, staleDate: nil), dismissalPolicy: .immediate) }
        }
        liveActivityID = nil
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
