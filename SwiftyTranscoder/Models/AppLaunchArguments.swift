/// Removes known GUI launch arguments before deciding between the window and CLI.
/// Unknown arguments remain intact so CLI mistakes still produce usage errors.
enum AppLaunchArguments {
    static func userArguments(_ arguments: [String]) -> [String] {
        var result: [String] = []
        var index = 0
        var positionalOnly = false
        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--" { positionalOnly = true }
            if !positionalOnly, argument.hasPrefix("-psn_") {
                index += 1
                continue
            }
            if !positionalOnly,
               ["-NSDocumentRevisionsDebugMode", "-NSPersistenceIgnoreState"].contains(argument),
               index + 1 < arguments.count,
               ["YES", "NO"].contains(arguments[index + 1]) {
                index += 2
                continue
            }
            result.append(argument)
            index += 1
        }
        return result
    }
}
