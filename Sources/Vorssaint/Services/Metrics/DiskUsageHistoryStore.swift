// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// A 30-day disk-usage-percentage history, persisted across launches.
///
/// This is deliberately not another `MetricHistory` ring buffer: those hold a
/// few minutes of samples in memory only, which is right for CPU/GPU/memory/
/// network (they move fast enough that a short rolling window shows a real
/// shape) but wrong for disk usage — it moves so slowly that a short window
/// is indistinguishable from a flat line. iStat Menus' own disk history goes
/// out to 30 days for the same reason. So this stores far fewer, far more
/// widely spaced samples (one per hour, ~720 over 30 days) in a small JSON
/// file that survives app relaunches, rather than a fast in-memory buffer
/// that doesn't need to.
final class DiskUsageHistoryStore {
    struct Sample: Codable {
        let timestamp: Date
        let fraction: Double
    }

    private static let sampleInterval: TimeInterval = 3600 // 1 hour
    private static let retentionInterval: TimeInterval = 30 * 24 * 3600 // 30 days
    private static let fileName = "disk-usage-history.json"

    private var samples: [Sample]
    private let fileURL: URL?

    init() {
        let url = PrivateFileStore.containerURL?.appendingPathComponent(Self.fileName)
        fileURL = url
        if let url, let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([Sample].self, from: data) {
            samples = decoded
        } else {
            samples = []
        }
    }

    /// Oldest → newest fractions, ready to hand straight to the sparkline
    /// renderer the same way a `MetricHistory.values` array would be.
    var values: [Double] { samples.map(\.fraction) }

    /// Records `fraction` if at least an hour has passed since the last
    /// recorded sample (or there isn't one yet), then prunes anything older
    /// than 30 days and persists. Safe to call on every regular monitor
    /// tick — most calls are no-ops until the hour is up.
    func record(fraction: Double, now: Date = Date()) {
        if let last = samples.last, now.timeIntervalSince(last.timestamp) < Self.sampleInterval {
            return
        }
        samples.append(Sample(timestamp: now, fraction: fraction))
        let cutoff = now.addingTimeInterval(-Self.retentionInterval)
        samples.removeAll { $0.timestamp < cutoff }
        save()
    }

    private func save() {
        guard let fileURL, let container = PrivateFileStore.containerURL else { return }
        guard let data = try? JSONEncoder().encode(samples) else { return }
        PrivateFileStore.createDirectory(at: container)
        PrivateFileStore.write(data, to: fileURL)
    }
}
