import Foundation
import PackagePlugin

@main
struct BuildMetalShaders: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: any Target) async throws -> [Command] {
        guard let sourceModule = target as? SourceModuleTarget else {
            return []
        }

        // Keep the human-authored shader source in the package, but generate the runtime
        // `.metallib` into the plugin work directory so SwiftPM bundles the compiled output.
        let shaderSourceURL = sourceModule.directoryURL.appendingPathComponent(
            "Shaders/VoxelShaders.metal")
        guard FileManager.default.fileExists(atPath: shaderSourceURL.path) else {
            return []
        }

        let tool = try context.tool(named: "MetalShaderCompiler")
        let outputFileURL = context.pluginWorkDirectoryURL.appendingPathComponent(
            "VoxelShaders.metallib")

        return [
            .buildCommand(
                displayName: "Compiling Metal shaders for \(target.name)",
                executable: tool.url,
                arguments: [
                    shaderSourceURL.path,
                    outputFileURL.path,
                ],
                inputFiles: [shaderSourceURL],
                outputFiles: [outputFileURL])
        ]
    }
}
