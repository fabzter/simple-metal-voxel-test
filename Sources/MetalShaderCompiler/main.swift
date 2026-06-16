import Foundation

@main
struct MetalShaderCompiler {
    static func main() throws {
        let arguments = CommandLine.arguments
        guard arguments.count == 3 else {
            throw CompilerError.invalidArguments
        }

        let inputPath = arguments[1]
        let outputURL = URL(fileURLWithPath: arguments[2], isDirectory: false)
        let fileManager = FileManager.default

        try fileManager.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)

        let airURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("air")
        let metallibURL = outputURL

        defer {
            try? fileManager.removeItem(at: airURL)
        }

        try run(
            executable: "/usr/bin/xcrun",
            arguments: ["-sdk", "macosx", "metal", "-c", inputPath, "-o", airURL.path])

        try run(
            executable: "/usr/bin/xcrun",
            arguments: ["-sdk", "macosx", "metallib", airURL.path, "-o", metallibURL.path])
    }

    private static func run(executable: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let stderr = Pipe()
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: errorData, encoding: .utf8) ?? "Unknown tool failure"
            throw CompilerError.commandFailed(message)
        }
    }
}

enum CompilerError: LocalizedError {
    case invalidArguments
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidArguments:
            return "Expected: MetalShaderCompiler <input.metal> <output.metallib>"
        case .commandFailed(let message):
            return message
        }
    }
}
