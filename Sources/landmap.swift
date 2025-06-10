// Build CLI Tool
// A tool for managing project builds with global configuration support
//
// Build by Landmap created at 2025, Jun 10

import ArgumentParser
import Foundation

struct ProjectConfig: Codable {
    let name: String
    let path: String
    let buildCommand: String
    let testCommand: String?
    let dependencies: [String]
    let environment: [String: String]
    let createdAt: Date
    let lastModified: Date

    init(
        name: String, path: String, buildCommand: String, testCommand: String? = nil,
        dependencies: [String] = [], environment: [String: String] = [:]
    ) {
        self.name = name
        self.path = path
        self.buildCommand = buildCommand
        self.testCommand = testCommand
        self.dependencies = dependencies
        self.environment = environment
        self.createdAt = Date()
        self.lastModified = Date()
    }
}

struct GlobalConfig: Codable {
    var projects: [String: ProjectConfig] = [:]
    var defaultSettings: [String: String] = [:]
    var lastUpdated: Date = Date()
}

struct Status: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show status and information about the current project"
    )

    @Option(name: .long, help: "Project path (defaults to current directory)")
    var path: String?

    mutating func run() throws {
        let projectPath = path ?? FileManager.default.currentDirectoryPath
        let absolutePath = URL(fileURLWithPath: projectPath).standardizedFileURL.path
        let projectKey = ConfigManager.getProjectKey(for: absolutePath)

        let config = try ConfigManager.loadGlobalConfig()

        guard let projectConfig = config.projects[projectKey] else {
            print("❌ No project configuration found for path: \(absolutePath)")
            print("   Run 'build-tool init' to initialize this project")
            return
        }

        print("📊 Project Status")
        print("=" * 50)
        print("Name: \(projectConfig.name)")
        print("Path: \(projectConfig.path)")
        print("Build Command: \(projectConfig.buildCommand)")

        if let testCommand = projectConfig.testCommand {
            print("Test Command: \(testCommand)")
        } else {
            print("Test Command: Not configured")
        }

        if !projectConfig.dependencies.isEmpty {
            print("Dependencies: \(projectConfig.dependencies.joined(separator: ", "))")
        }

        if !projectConfig.environment.isEmpty {
            print("Environment Variables:")
            for (key, value) in projectConfig.environment.sorted(by: { $0.key < $1.key }) {
                print("  \(key) = \(value)")
            }
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        print("Created: \(formatter.string(from: projectConfig.createdAt))")
        print("Last Modified: \(formatter.string(from: projectConfig.lastModified))")

        // Check if build command would work
        print("\n🔍 Environment Check:")
        let buildCommandParts = projectConfig.buildCommand.split(separator: " ")
        if let firstCommand = buildCommandParts.first {
            let checkResult = checkCommandAvailable(String(firstCommand))
            if checkResult {
                print("✅ Build command '\(firstCommand)' is available")
            } else {
                print("⚠️  Build command '\(firstCommand)' may not be available")
            }
        }
    }

    private func checkCommandAvailable(_ command: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [command]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}

// MARK: - Configuration Manager
class ConfigManager {
    private static let configDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".build-tools")
    private static let configFile = configDir.appendingPathComponent("config.json")

    static func ensureConfigDirectory() throws {
        if !FileManager.default.fileExists(atPath: configDir.path) {
            try FileManager.default.createDirectory(
                at: configDir, withIntermediateDirectories: true)
        }
    }

    static func loadGlobalConfig() throws -> GlobalConfig {
        try ensureConfigDirectory()

        guard FileManager.default.fileExists(atPath: configFile.path) else {
            return GlobalConfig()
        }

        let data = try Data(contentsOf: configFile)
        return try JSONDecoder().decode(GlobalConfig.self, from: data)
    }

    static func saveGlobalConfig(_ config: GlobalConfig) throws {
        try ensureConfigDirectory()
        let data = try JSONEncoder().encode(config)
        try data.write(to: configFile)
    }

    static func getProjectKey(for path: String) -> String {
        return URL(fileURLWithPath: path).standardizedFileURL.path
    }
}

// MARK: - CLI Commands
@main
struct BuildTool: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "build-tool",
        abstract: "A CLI tool for managing project builds with global configuration",
        subcommands: [Init.self, Build.self, List.self, Remove.self, Config.self, Status.self],
        defaultSubcommand: List.self
    )
}

// MARK: - Init Command
struct Init: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Initialize a new project configuration"
    )

    @Option(name: .long, help: "Project name")
    var name: String?

    @Option(name: .long, help: "Project path (defaults to current directory)")
    var path: String?

    @Option(name: .long, help: "Build command")
    var buildCommand: String = "make"

    @Option(name: .long, help: "Test command")
    var testCommand: String?

    @Flag(name: .long, help: "Interactive mode")
    var interactive: Bool = false

    mutating func run() throws {
        let projectPath = path ?? FileManager.default.currentDirectoryPath
        let absolutePath = URL(fileURLWithPath: projectPath).standardizedFileURL.path

        var config = try ConfigManager.loadGlobalConfig()
        let projectKey = ConfigManager.getProjectKey(for: absolutePath)

        if config.projects.keys.contains(projectKey) {
            print("⚠️  Project already exists at path: \(absolutePath)")
            return
        }

        let projectName: String
        let finalBuildCommand: String
        let finalTestCommand: String?

        if interactive {
            projectName = readInput(
                "Project name: ",
                default: name ?? URL(fileURLWithPath: absolutePath).lastPathComponent)
            finalBuildCommand = readInput("Build command: ", default: buildCommand)
            finalTestCommand = readInput("Test command (optional): ", default: testCommand)
        } else {
            projectName = name ?? URL(fileURLWithPath: absolutePath).lastPathComponent
            finalBuildCommand = buildCommand
            finalTestCommand = testCommand
        }

        let projectConfig = ProjectConfig(
            name: projectName,
            path: absolutePath,
            buildCommand: finalBuildCommand,
            testCommand: finalTestCommand?.isEmpty == false ? finalTestCommand : nil
        )

        config.projects[projectKey] = projectConfig
        config.lastUpdated = Date()

        try ConfigManager.saveGlobalConfig(config)

        print("✅ Project '\(projectName)' initialized successfully!")
        print("   Path: \(absolutePath)")
        print("   Build command: \(finalBuildCommand)")
        if let testCmd = finalTestCommand {
            print("   Test command: \(testCmd)")
        }
    }

    private func readInput(_ prompt: String, default: String?) -> String {
        print(prompt, terminator: "")
        if let defaultValue = `default`, !defaultValue.isEmpty {
            print("[\(defaultValue)] ", terminator: "")
        }

        if let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines) {
            return input.isEmpty ? (`default` ?? "") : input
        }
        return `default` ?? ""
    }
}

// MARK: - Build Command
struct Build: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Build a project using its saved configuration"
    )

    @Option(name: .long, help: "Project path (defaults to current directory)")
    var path: String?

    @Flag(name: .long, help: "Run tests after build")
    var test: Bool = false

    @Flag(name: .long, help: "Verbose output")
    var verbose: Bool = false

    mutating func run() throws {
        let projectPath = path ?? FileManager.default.currentDirectoryPath
        let absolutePath = URL(fileURLWithPath: projectPath).standardizedFileURL.path
        let projectKey = ConfigManager.getProjectKey(for: absolutePath)

        let config = try ConfigManager.loadGlobalConfig()

        guard let projectConfig = config.projects[projectKey] else {
            print("❌ No project configuration found for path: \(absolutePath)")
            print("   Run 'build-tool init' to initialize this project")
            return
        }

        print("🔨 Building project '\(projectConfig.name)'...")
        if verbose {
            print("   Path: \(projectConfig.path)")
            print("   Command: \(projectConfig.buildCommand)")
        }

        let buildResult = try runCommand(projectConfig.buildCommand, in: projectConfig.path)

        if buildResult.success {
            print("✅ Build completed successfully!")

            if test, let testCommand = projectConfig.testCommand {
                print("🧪 Running tests...")
                let testResult = try runCommand(testCommand, in: projectConfig.path)

                if testResult.success {
                    print("✅ Tests passed!")
                } else {
                    print("❌ Tests failed!")
                    if verbose {
                        print(testResult.output)
                    }
                }
            }
        } else {
            print("❌ Build failed!")
            if verbose {
                print(buildResult.output)
            }
        }
    }

    private func runCommand(_ command: String, in directory: String) throws -> (
        success: Bool, output: String
    ) {
        let process = Process()
        let pipe = Pipe()

        process.currentDirectoryURL = URL(fileURLWithPath: directory)
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", command]
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        return (success: process.terminationStatus == 0, output: output)
    }
}

// MARK: - List Command
struct List: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List all configured projects"
    )

    @Flag(name: .long, help: "Show detailed information")
    var verbose: Bool = false

    mutating func run() throws {
        let config = try ConfigManager.loadGlobalConfig()

        if config.projects.isEmpty {
            print("No projects configured yet.")
            print("Run 'build-tool init' to add a project.")
            return
        }

        print("📋 Configured Projects:")
        print("=" * 50)

        for (_, project) in config.projects.sorted(by: { $0.value.name < $1.value.name }) {
            print("• \(project.name)")
            print("  Path: \(project.path)")
            print("  Build: \(project.buildCommand)")

            if let testCommand = project.testCommand {
                print("  Test: \(testCommand)")
            }

            if verbose {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                formatter.timeStyle = .short
                print("  Created: \(formatter.string(from: project.createdAt))")
            }

            print("")
        }
    }
}

// MARK: - Remove Command
struct Remove: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Remove a project configuration"
    )

    @Option(name: .long, help: "Project path (defaults to current directory)")
    var path: String?

    mutating func run() throws {
        let projectPath = path ?? FileManager.default.currentDirectoryPath
        let absolutePath = URL(fileURLWithPath: projectPath).standardizedFileURL.path
        let projectKey = ConfigManager.getProjectKey(for: absolutePath)

        var config = try ConfigManager.loadGlobalConfig()

        guard let projectConfig = config.projects[projectKey] else {
            print("❌ No project configuration found for path: \(absolutePath)")
            return
        }

        config.projects.removeValue(forKey: projectKey)
        config.lastUpdated = Date()

        try ConfigManager.saveGlobalConfig(config)

        print("✅ Project '\(projectConfig.name)' removed successfully!")
    }
}

// MARK: - Config Command
struct Config: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Manage global configuration settings"
    )

    @Option(name: .long, help: "Set a global setting (key=value)")
    var set: String?

    @Option(name: .long, help: "Get a global setting")
    var get: String?

    @Flag(name: .long, help: "List all global settings")
    var list: Bool = false

    mutating func run() throws {
        var config = try ConfigManager.loadGlobalConfig()

        if let setting = set {
            let parts = setting.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else {
                print("❌ Invalid format. Use: key=value")
                return
            }

            let key = String(parts[0])
            let value = String(parts[1])

            config.defaultSettings[key] = value
            config.lastUpdated = Date()

            try ConfigManager.saveGlobalConfig(config)
            print("✅ Setting '\(key)' = '\(value)' saved")

        } else if let key = get {
            if let value = config.defaultSettings[key] {
                print("\(key) = \(value)")
            } else {
                print("❌ Setting '\(key)' not found")
            }

        } else if list {
            if config.defaultSettings.isEmpty {
                print("No global settings configured.")
            } else {
                print("Global Settings:")
                for (key, value) in config.defaultSettings.sorted(by: { $0.key < $1.key }) {
                    print("  \(key) = \(value)")
                }
            }
        } else {
            print("Use --set, --get, or --list to manage global settings")
        }
    }
}

// MARK: - String Extension for Repetition
extension String {
    static func * (left: String, right: Int) -> String {
        return String(repeating: left, count: right)
    }
}
