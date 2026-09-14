import Foundation
import os

enum StateStore {
    static let dir = URL(fileURLWithPath: "/Library/Application Support/ThermalControl")
    static let file = dir.appendingPathComponent("state.json")

    static func load() -> PersistedState? {
        do {
            let data = try Data(contentsOf: file)
            let state = try JSONDecoder().decode(PersistedState.self, from: data)
            Logger.state.info("loaded state → fan=\(state.fanMode, privacy: .public) upper=\(state.upper, privacy: .public) lower=\(state.lower, privacy: .public)")
            return state
        } catch {
            // Missing file is the normal first-run case; decode corruption is worth surfacing.
            if (error as NSError).code != NSFileReadNoSuchFileError {
                Logger.state.error("load failed: \(error.localizedDescription, privacy: .public)")
            }
            return nil
        }
    }

    static func save(_ s: PersistedState) {
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(s)
            try data.write(to: file, options: .atomic)
        } catch {
            Logger.state.error("save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func remove() {
        do {
            try FileManager.default.removeItem(at: file)
        } catch {
            Logger.state.error("remove failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}