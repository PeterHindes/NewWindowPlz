import os

enum Log {
    private static let subsystem = "com.peter.newwindowplz"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let dock = Logger(subsystem: subsystem, category: "dock")
    static let action = Logger(subsystem: subsystem, category: "action")
    static let overlay = Logger(subsystem: subsystem, category: "overlay")
    static let permissions = Logger(subsystem: subsystem, category: "permissions")
}
