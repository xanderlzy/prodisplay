import OSLog

/// Read with: log show --last 1h --predicate 'subsystem == "local.prodisplay.ProDisplay"'
enum Log {
    static let brightness = Logger(subsystem: "local.prodisplay.ProDisplay", category: "brightness")
}
