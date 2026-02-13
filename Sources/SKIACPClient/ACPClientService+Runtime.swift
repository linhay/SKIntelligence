import Foundation
import SKIACP

public extension ACPClientService {
    /// Installs local runtime adapters for ACP client-side methods.
    /// This is a non-ACP extension helper and does not add/alter ACP protocol methods.
    func installRuntimes(
        filesystem: (any ACPFilesystemRuntime)? = nil,
        terminal: (any ACPTerminalRuntime)? = nil
    ) {
        if let filesystem {
            setReadTextFileHandler { params in
                try await filesystem.readTextFile(params)
            }
            setWriteTextFileHandler { params in
                try await filesystem.writeTextFile(params)
            }
        }

        if let terminal {
            setTerminalCreateHandler { params in
                try await terminal.create(params)
            }
            setTerminalOutputHandler { params in
                try await terminal.output(params)
            }
            setTerminalWaitForExitHandler { params in
                try await terminal.waitForExit(params)
            }
            setTerminalKillHandler { params in
                try await terminal.kill(params)
            }
            setTerminalReleaseHandler { params in
                try await terminal.release(params)
            }
        }
    }
}
