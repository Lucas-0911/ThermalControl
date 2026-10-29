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

    @discardableResult
    static func save(_ s: PersistedState) -> Result<Void, Error> {
        save(s, to: file)
    }

    @discardableResult
    static func save(_ s: PersistedState, to destination: URL) -> Result<Void, Error> {
        do {
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(s.safeForPersistence)
            try data.write(to: destination, options: .atomic)
            return .success(())
        } catch {
            Logger.state.error("save failed: \(error.localizedDescription, privacy: .public)")
            return .failure(error)
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