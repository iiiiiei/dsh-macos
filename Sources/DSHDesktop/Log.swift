import Foundation

/// 无缓冲日志（stderr），便于从终端 / 自测捕获运行轨迹
enum Log {
    static func info(_ message: String) {
        let line = "[DSH] \(message)\n"
        FileHandle.standardError.write(Data(line.utf8))
    }
}
