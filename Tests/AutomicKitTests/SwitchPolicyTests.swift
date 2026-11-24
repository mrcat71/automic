import AutomicKit
import Foundation
import Testing

struct SwitchPolicyTests {
    private let ranking = PriorityList(entries: [
        PriorityEntry(uid: "headset", name: "Work Headset"),
        PriorityEntry(uid: "usb-mic", name: "Home Mic"),
        PriorityEntry(uid: "builtin", name: "MacBook Microphone"),
    ])
    private let start = Date(timeIntervalSinceReferenceDate: 1000)

    @Test(arguments: [
        (["headset", "builtin"], "builtin", "headset"),
        (["usb-mic", "builtin"], "builtin", "usb-mic"),
        (["usb-mic", "builtin"], "usb-mic", nil),
        (["builtin"], "headset", "builtin"),
        ([], "builtin", nil),
        (["unranked"], "builtin", nil),
    ] as [(Set<String>, String?, String?)])
    func picksTheHighestConnected(connected: Set<String>, current: String?, expected: String?) {
        var policy = SwitchPolicy()
        policy.devicesChanged(at: start)
        #expect(policy.decide(list: ranking, connected: connected, current: current) == expected)
    }

    @Test func ownChangeIsNotAManualPick() {
        var policy = SwitchPolicy()
        policy.devicesChanged(at: start)
        #expect(policy.decide(list: ranking, connected: ["headset", "builtin"], current: "builtin") == "headset")
        // Long after the device change, the notification for Automic's own switch arrives.
        #expect(policy.defaultChanged(to: "headset", at: start + 30) == false)
        #expect(!policy.isOverridden)
    }

    @Test func manualPickIsKeptUntilTheNextDeviceChange() {
        var policy = SwitchPolicy()
        let connected: Set<String> = ["headset", "builtin"]
        policy.devicesChanged(at: start)
        _ = policy.decide(list: ranking, connected: connected, current: "builtin")
        _ = policy.defaultChanged(to: "headset", at: start + 1)

        #expect(policy.defaultChanged(to: "builtin", at: start + 60) == false)
        #expect(policy.isOverridden)
        #expect(policy.decide(list: ranking, connected: connected, current: "builtin") == nil)

        policy.devicesChanged(at: start + 120)
        #expect(!policy.isOverridden)
        #expect(policy.decide(list: ranking, connected: connected, current: "builtin") == "headset")
    }

    @Test func rankingChangeEndsTheManualPick() {
        var policy = SwitchPolicy()
        _ = policy.defaultChanged(to: "builtin", at: start)
        #expect(policy.isOverridden)
        policy.rankingChanged()
        #expect(policy.decide(list: ranking, connected: ["headset", "builtin"], current: "builtin") == "headset")
    }

    @Test(arguments: [
        (1.5, true, false),
        (2.9, true, false),
        (3.0, false, true),
        (10, false, true),
    ])
    func systemFollowUpAfterADeviceChange(after seconds: Double, reapply: Bool, overridden: Bool) {
        var policy = SwitchPolicy(settleInterval: 3)
        policy.devicesChanged(at: start)
        // AirPods connect while the wired headset ranks higher; macOS moves the default to them.
        #expect(policy.defaultChanged(to: "airpods", at: start + seconds) == reapply)
        #expect(policy.isOverridden == overridden)
    }

    @Test func failedSwitchDoesNotSwallowTheNextChange() {
        var policy = SwitchPolicy()
        policy.devicesChanged(at: start)
        #expect(policy.decide(list: ranking, connected: ["headset"], current: "builtin") == "headset")
        policy.switchFailed()
        // A later change to the same device is a pick by hand, not Automic's echo.
        #expect(policy.defaultChanged(to: "headset", at: start + 60) == false)
        #expect(policy.isOverridden)
    }
}
