/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import Shared
import Account
import SwiftyJSON
import Telemetry

fileprivate let log = Logger.syncLogger

public enum SyncReason: String {
    case startup = "startup"
    case scheduled = "scheduled"
    case backgrounded = "backgrounded"
    case user = "user"
    case syncNow = "syncNow"
    case didLogin = "didLogin"
}

public enum SyncPingReason: String {
    case shutdown = "shutdown"
    case schedule = "schedule"
    case idChanged = "idchanged"
}

public protocol Stats {
    func hasData() -> Bool
}

private protocol DictionaryRepresentable {
    func asDictionary() -> [String: Any]
}

public struct SyncUploadStats: Stats {
    var sent: Int = 0
    var sentFailed: Int = 0

    public func hasData() -> Bool {
        return sent > 0 || sentFailed > 0
    }
}

extension SyncUploadStats: DictionaryRepresentable {
    func asDictionary() -> [String: Any] {
        return [
            "sent": sent,
            "sentFailed": sentFailed
        ]
    }
}

public struct SyncDownloadStats: Stats {
    var applied: Int = 0
    var succeeded: Int = 0
    var failed: Int = 0
    var newFailed: Int = 0
    var reconciled: Int = 0

    public func hasData() -> Bool {
        return applied > 0 ||
            succeeded > 0 ||
            failed > 0 ||
            newFailed > 0 ||
            reconciled > 0
    }
}

extension SyncDownloadStats: DictionaryRepresentable {
    func asDictionary() -> [String: Any] {
        return [
            "applied": applied,
            "succeeded": succeeded,
            "failed": failed,
            "newFailed": newFailed,
            "reconciled": reconciled
        ]
    }
}

// TODO(sleroux): Implement various bookmark validation issues we can run into.
public struct ValidationStats: Stats {
    public func hasData() -> Bool {
        return false
    }
}

public class StatsSession {
    var took: Int64 = 0
    var when: Int64?

    private var startUptime: Int64?

    public func start(when: Int64 = Int64(Date.now())) {
        self.when = when
        self.startUptime = Int64(DispatchTime.now().uptimeNanoseconds)
    }

    public func hasStarted() -> Bool {
        return startUptime != nil
    }

    public func end() -> Self {
        guard let startUptime = startUptime else {
            assertionFailure("SyncOperationStats called end without first calling start!")
            return self
        }

        // Casting to Int64 should be safe since we're using uptime since boot in both cases.
        took = Int64(DispatchTime.now().uptimeNanoseconds) - Int64(startUptime)
        return self
    }
}

// Stats about a single engine's sync.
public class SyncEngineStatsSession: StatsSession {
    public let collection: String
    public var failureReason: Any?
    public var validationStats: ValidationStats?

    private(set) var uploadStats: SyncUploadStats
    private(set) var downloadStats: SyncDownloadStats

    public init(collection: String) {
        self.collection = collection
        self.uploadStats = SyncUploadStats()
        self.downloadStats = SyncDownloadStats()
    }

    public func recordDownload(stats: SyncDownloadStats) {
        self.downloadStats.applied += stats.applied
        self.downloadStats.succeeded += stats.succeeded
        self.downloadStats.failed += stats.failed
        self.downloadStats.newFailed += stats.newFailed
        self.downloadStats.reconciled += stats.reconciled
    }

    public func recordUpload(stats: SyncUploadStats) {
        self.uploadStats.sent += stats.sent
        self.uploadStats.sentFailed += stats.sentFailed
    }
}

extension SyncEngineStatsSession: DictionaryRepresentable {
    func asDictionary() -> [String : Any] {
        return [
            "name": collection,
            "took": took,
            "incoming": downloadStats.asDictionary(),
            "outgoing": uploadStats.asDictionary()
        ]
    }
}

// Stats and metadata for a sync operation.
public class SyncOperationStatsSession: StatsSession {
    public let why: SyncReason
    public var uid: String?
    public var deviceID: String?

    fileprivate let didLogin: Bool

    public init(why: SyncReason, uid: String, deviceID: String?) {
        self.why = why
        self.uid = uid
        self.deviceID = deviceID
        self.didLogin = (why == .didLogin)
    }
}

extension SyncOperationStatsSession: DictionaryRepresentable {
    func asDictionary() -> [String : Any] {
        let whenValue = when ?? 0
        return [
            "when": whenValue,
            "took": took,
            "didLogin": didLogin,
            "why": why.rawValue
        ]
    }
}

public struct SyncPing: TelemetryPing {
    public var payload: JSON

    public init(opStats: SyncOperationStatsSession, engineStats: [SyncEngineStatsSession]) {
        var ping: [String: Any] = [
            "version": 1,
            "discarded": 0,
            "why": SyncPingReason.schedule.rawValue,
            "uid": "testUID",
            "deviceID": "testDeviceID"
        ]

        var syncOp = opStats.asDictionary()
        syncOp["engines"] = engineStats.map { $0.asDictionary() }
        ping["syncs"] = [syncOp]
        
        payload = JSON(ping)
    }
}
