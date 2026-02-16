import Foundation

public enum ACPMethodCatalog {
    public static let unstableBaseline: Set<String> = [
        ACPMethods.cancelRequest,
        ACPMethods.initialize,
        ACPMethods.authenticate,
        ACPMethods.sessionCancel,
        ACPMethods.sessionFork,
        ACPMethods.sessionList,
        ACPMethods.sessionLoad,
        ACPMethods.sessionNew,
        ACPMethods.sessionPrompt,
        ACPMethods.sessionResume,
        ACPMethods.sessionSetConfigOption,
        ACPMethods.sessionSetMode,
        ACPMethods.sessionSetModel,
        ACPMethods.sessionRequestPermission,
        ACPMethods.sessionUpdate,
        ACPMethods.fsReadTextFile,
        ACPMethods.fsWriteTextFile,
        ACPMethods.terminalCreate,
        ACPMethods.terminalKill,
        ACPMethods.terminalOutput,
        ACPMethods.terminalRelease,
        ACPMethods.terminalWaitForExit,
    ]

    public static let stableBaseline: Set<String> = [
        ACPMethods.initialize,
        ACPMethods.authenticate,
        ACPMethods.sessionCancel,
        ACPMethods.sessionLoad,
        ACPMethods.sessionNew,
        ACPMethods.sessionPrompt,
        ACPMethods.sessionSetConfigOption,
        ACPMethods.sessionSetMode,
        ACPMethods.sessionRequestPermission,
        ACPMethods.sessionUpdate,
        ACPMethods.fsReadTextFile,
        ACPMethods.fsWriteTextFile,
        ACPMethods.terminalCreate,
        ACPMethods.terminalKill,
        ACPMethods.terminalOutput,
        ACPMethods.terminalRelease,
        ACPMethods.terminalWaitForExit,
    ]

    public static let projectExtensions: Set<String> = [
        ACPMethods.logout,
        ACPMethods.sessionDelete,
        ACPMethods.sessionExport,
    ]

    public static let allSupported: Set<String> = unstableBaseline.union(projectExtensions)
}
