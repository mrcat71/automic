import AutomicKit
import Foundation
import Testing

private func list(_ uids: String..., disabled: Set<String> = []) -> PriorityList {
    PriorityList(entries: uids.map { PriorityEntry(uid: $0, name: $0.uppercased(), isDisabled: disabled.contains($0)) })
}

private func uids(_ list: PriorityList) -> [String] {
    list.entries.map(\.uid)
}

struct PriorityListTests {
    struct MergeCase: CustomTestStringConvertible, Sendable {
        let name: String
        let start: PriorityList
        let devices: [String]
        let current: String?
        let expected: [String]
        let changed: Bool
        var testDescription: String { name }
    }

    @Test(arguments: [
        MergeCase(name: "first merge puts the current default first", start: list(), devices: ["a", "b", "c"], current: "b", expected: ["b", "a", "c"], changed: true),
        MergeCase(name: "first merge without a current default keeps CoreAudio order", start: list(), devices: ["a", "b"], current: nil, expected: ["a", "b"], changed: true),
        MergeCase(name: "new devices go to the bottom", start: list("x", "y"), devices: ["new", "y"], current: "new", expected: ["x", "y", "new"], changed: true),
        MergeCase(name: "known devices keep their rank", start: list("x", "y"), devices: ["y", "x"], current: "y", expected: ["x", "y"], changed: false),
        MergeCase(name: "disconnected devices are remembered", start: list("x", "y"), devices: [], current: nil, expected: ["x", "y"], changed: false),
    ])
    func merge(_ testCase: MergeCase) {
        var subject = testCase.start
        let devices = testCase.devices.map { AudioDevice(uid: $0, name: $0.uppercased()) }
        let changed = subject.merge(devices, current: testCase.current)
        #expect(uids(subject) == testCase.expected)
        #expect(changed == testCase.changed)
    }

    @Test func mergeRefreshesNameAndTransport() {
        var subject = list("x")
        let changed = subject.merge([AudioDevice(uid: "x", name: "Renamed", transport: .usb)])
        #expect(changed)
        #expect(subject.entries[0].name == "Renamed")
        #expect(subject.entries[0].transport == .usb)
    }

    @Test(arguments: [
        ([0], 3, ["b", "c", "a", "d"]),
        ([3], 0, ["d", "a", "b", "c"]),
        ([1], 1, ["a", "b", "c", "d"]),
        ([1], 2, ["a", "b", "c", "d"]),
        ([0, 2], 4, ["b", "d", "a", "c"]),
        ([2], 99, ["a", "b", "d", "c"]),
        ([9], 0, ["a", "b", "c", "d"]),
    ])
    func moveFromOffsets(offsets: [Int], destination: Int, expected: [String]) {
        var subject = list("a", "b", "c", "d")
        subject.move(fromOffsets: IndexSet(offsets), toOffset: destination)
        #expect(uids(subject) == expected)
    }

    @Test func mergeStampsLastSeenOnlyOnConnectedDevices() {
        let earlier = Date(timeIntervalSinceReferenceDate: 100)
        let now = Date(timeIntervalSinceReferenceDate: 200)
        var subject = PriorityList(entries: [
            PriorityEntry(uid: "gone", name: "Gone", lastSeen: earlier),
            PriorityEntry(uid: "here", name: "Here", lastSeen: earlier),
        ])
        subject.merge([AudioDevice(uid: "here", name: "Here"), AudioDevice(uid: "new", name: "New")], seenAt: now)
        #expect(subject.entries.map(\.lastSeen) == [earlier, now, now])
    }

    @Test func decodesEntriesSavedWithoutLastSeen() throws {
        let json = #"{"entries":[{"uid":"a","name":"A","transport":"usb","isDisabled":false}]}"#
        let decoded = try JSONDecoder().decode(PriorityList.self, from: Data(json.utf8))
        #expect(decoded.entries[0].lastSeen == nil)
        #expect(decoded.entries[0].transport == .usb)
    }

    // Full list a b c d e; the view hides b and d.
    @Test(arguments: [
        ([0], 3, ["c", "b", "e", "d", "a"]),
        ([2], 0, ["e", "b", "a", "d", "c"]),
        ([1], 1, ["a", "b", "c", "d", "e"]),
        ([9], 0, ["a", "b", "c", "d", "e"]),
    ])
    func moveVisibleKeepsHiddenEntriesInPlace(offsets: [Int], destination: Int, expected: [String]) {
        var subject = list("a", "b", "c", "d", "e")
        subject.move(visible: ["a", "c", "e"], fromOffsets: IndexSet(offsets), toOffset: destination)
        #expect(uids(subject) == expected)
    }

    @Test func moveVisibleIgnoresUnknownDevices() {
        var subject = list("a", "b")
        subject.move(visible: ["a", "missing"], fromOffsets: [0], toOffset: 2)
        #expect(uids(subject) == ["a", "b"])
    }

    @Test(arguments: [
        ("b", -1, ["b", "a", "c"]),
        ("b", 1, ["a", "c", "b"]),
        ("a", -1, ["a", "b", "c"]),
        ("c", 5, ["a", "b", "c"]),
        ("missing", 1, ["a", "b", "c"]),
    ])
    func moveByStep(uid: String, steps: Int, expected: [String]) {
        var subject = list("a", "b", "c")
        subject.move(uid, by: steps)
        #expect(uids(subject) == expected)
    }

    @Test func forgetAndDisable() {
        var subject = list("a", "b", "c")
        subject.forget("b")
        subject.setDisabled("c", true)
        #expect(uids(subject) == ["a", "c"])
        #expect(subject.entries[1].isDisabled)
        #expect(subject.rank(of: "c") == 1)
        #expect(subject.rank(of: "b") == nil)
    }

    @Test(arguments: [
        (["a", "b", "c"], ["b", "c"], "b"),
        (["a", "b", "c"], ["c", "a"], "a"),
        (["a", "b", "c"], [], nil),
        (["a", "b", "c"], ["unranked"], nil),
    ] as [([String], Set<String>, String?)])
    func choose(order: [String], connected: Set<String>, expected: String?) {
        let subject = PriorityList(entries: order.map { PriorityEntry(uid: $0, name: $0) })
        #expect(subject.choose(connected: connected) == expected)
    }

    @Test func chooseSkipsDisabled() {
        let subject = list("monitor", "headset", "builtin", disabled: ["monitor"])
        #expect(subject.choose(connected: ["monitor", "builtin"]) == "builtin")
        #expect(subject.choose(connected: ["monitor"]) == nil)
    }

    @Test func roundTripsThroughJSON() throws {
        let subject = list("a", "b", disabled: ["b"])
        let decoded = try JSONDecoder().decode(PriorityList.self, from: JSONEncoder().encode(subject))
        #expect(decoded == subject)
    }
}
