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
        // The Metal compiler's clang frontend writes its module cache to the
        // system cache directory by default, which the SwiftPM build-plugin
        // sandbox blocks with "Operation not permitted". Redirect it into the
        // plugin work directory (a sandbox-allowed path) so `metal` can build
        // the metal_stdlib/metal_types modules during CI and local builds.
        let moduleCacheURL = context.pluginWorkDirectoryURL.appendingPathComponent(
            "ModuleCache")

        return [
            .buildCommand(
                displayName: "Compiling Metal shaders for \(target.name)",
                executable: tool.url,
                arguments: [
                    shaderSourceURL.path,
                    outputFileURL.path,
                    moduleCacheURL.path,
                ],
                inputFiles: [shaderSourceURL],
                outputFiles: [outputFileURL])
        ]
    }
}
