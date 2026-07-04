import Foundation

@main
struct MetalShaderCompiler {
    static func main() throws {
        let arguments = CommandLine.arguments
        guard arguments.count == 4 else {
            throw CompilerError.invalidArguments
        }

        let inputPath = arguments[1]
        let outputURL = URL(fileURLWithPath: arguments[2], isDirectory: false)
        let moduleCachePath = arguments[3]
        let fileManager = FileManager.default

        try fileManager.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try fileManager.createDirectory(
            at: URL(fileURLWithPath: moduleCachePath, isDirectory: true),
            withIntermediateDirectories: true)

        // Compile in two stages to match the standard Metal toolchain flow:
        // `.metal` source -> AIR intermediate -> `.metallib` runtime library.
        let airURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("air")
        let metallibURL = outputURL

        defer {
            try? fileManager.removeItem(at: airURL)
        }

        let metalExecutable = try resolveTool(named: "metal")
        let metallibExecutable = try resolveTool(named: "metallib")

        try run(
            executable: metalExecutable,
            arguments: ["-c", inputPath, "-o", airURL.path])

        try run(
            executable: metallibExecutable,
            arguments: [airURL.path, "-o", metallibURL.path])
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

    private static func resolveTool(named tool: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["-sdk", "macosx", "-find", tool]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
            let message =
                String(data: errorData, encoding: .utf8) ?? "Unknown tool resolution failure"
            throw CompilerError.commandFailed(message)
        }

        let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
        guard
            let output = String(data: outputData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !output.isEmpty
        else {
            throw CompilerError.commandFailed(
                "xcrun -sdk macosx -find \(tool) returned an empty path.")
        }

        return output
    }
}

enum CompilerError: LocalizedError {
    case invalidArguments
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidArguments:
            return "Expected: MetalShaderCompiler <input.metal> <output.metallib> <module-cache-dir>"
        case .commandFailed(let message):
            return message
        }
    }
}
