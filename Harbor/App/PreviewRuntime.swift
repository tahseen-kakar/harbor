import Foundation

enum PreviewRuntime {
    static var isActive: Bool {
        let environment = ProcessInfo.processInfo.environment

        return environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
            || environment["XCODE_RUNNING_FOR_PLAYGROUNDS"] == "1"
            || environment["PLAYGROUND_LOGGER_FILTER"] != nil
    }
}
