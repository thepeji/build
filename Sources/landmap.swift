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
    var customCommands: [String: String]
    let createdAt: Date
    var lastModified: Date

    init(
        name: String, path: String, buildCommand: String, testCommand: String? = nil,
        dependencies: [String] = [], environment: [String: String] = [:],
        customCommands: [String: String] = [:]
    ) {
        self.name = name
        self.path = path
        self.buildCommand = buildCommand
        self.testCommand = testCommand
        self.dependencies = dependencies
        self.environment = environment
        self.customCommands = customCommands
        self.createdAt = Date()
        self.lastModified = Date()
    }

    // Custom decoder to handle missing customCommands field in old configs
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        path = try container.decode(String.self, forKey: .path)
        buildCommand = try container.decode(String.self, forKey: .buildCommand)
        testCommand = try container.decodeIfPresent(String.self, forKey: .testCommand)
        dependencies = try container.decodeIfPresent([String].self, forKey: .dependencies) ?? []
        environment =
            try container.decodeIfPresent([String: String].self, forKey: .environment) ?? [:]
        customCommands =
            try container.decodeIfPresent([String: String].self, forKey: .customCommands) ?? [:]
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        lastModified = try container.decode(Date.self, forKey: .lastModified)
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

        if !projectConfig.customCommands.isEmpty {
            print("Custom Commands:")
            for (name, command) in projectConfig.customCommands.sorted(by: { $0.key < $1.key }) {
                print("  \(name) = \(command)")
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
        var finalCustomCommands: [String: String] = [:]

        if interactive {
            projectName = readInput(
                "Project name: ",
                default: name ?? URL(fileURLWithPath: absolutePath).lastPathComponent)
            finalBuildCommand = readInput("Build command: ", default: buildCommand)
            finalTestCommand = readInput("Test command (optional): ", default: testCommand)

            // Interactive custom commands
            print("Custom commands (press Enter when done):")
            while true {
                let customName = readInput(
                    "Custom command name (or press Enter to finish): ", default: nil)
                if customName.isEmpty { break }

                let customCmd = readInput("Command for '\(customName)': ", default: nil)
                if !customCmd.isEmpty {
                    finalCustomCommands[customName] = customCmd
                    print("  Added: \(customName) = \(customCmd)")
                }
            }
        } else {
            projectName = name ?? URL(fileURLWithPath: absolutePath).lastPathComponent
            finalBuildCommand = buildCommand
            finalTestCommand = testCommand
        }

        let projectConfig = ProjectConfig(
            name: projectName,
            path: absolutePath,
            buildCommand: finalBuildCommand,
            testCommand: finalTestCommand?.isEmpty == false ? finalTestCommand : nil,
            customCommands: finalCustomCommands
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
        if !finalCustomCommands.isEmpty {
            print("   Custom commands:")
            for (name, command) in finalCustomCommands.sorted(by: { $0.key < $1.key }) {
                print("     \(name) = \(command)")
            }
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

// MARK: - Run Command
struct Run: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Run a custom command for a project"
    )

    @Argument(help: "Name of the custom command to run")
    var commandName: String

    @Option(name: .long, help: "Project path (defaults to current directory)")
    var path: String?

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

        guard let command = projectConfig.customCommands[commandName] else {
            print("❌ Custom command '\(commandName)' not found for project '\(projectConfig.name)'")

            if !projectConfig.customCommands.isEmpty {
                print("   Available custom commands:")
                for (name, cmd) in projectConfig.customCommands.sorted(by: { $0.key < $1.key }) {
                    print("     \(name) = \(cmd)")
                }
            } else {
                print("   No custom commands configured for this project")
                print(
                    "   Use 'build-tool add-command --name <name> --command <command>' to add custom commands"
                )
            }
            return
        }

        print("🚀 Running custom command '\(commandName)' for project '\(projectConfig.name)'...")
        if verbose {
            print("   Path: \(projectConfig.path)")
            print("   Command: \(command)")
        }

        let result = try runCommand(command, in: projectConfig.path)

        if result.success {
            print("✅ Command '\(commandName)' completed successfully!")
            if verbose && !result.output.isEmpty {
                print("Output:")
                print(result.output)
            }
        } else {
            print("❌ Command '\(commandName)' failed!")
            if !result.output.isEmpty {
                print("Output:")
                print(result.output)
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

// MARK: - Add Command
struct AddCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "add-command",
        abstract: "Add or update a custom command for a project"
    )

    @Option(name: .long, help: "Name of the custom command")
    var name: String

    @Option(name: .long, help: "Command to execute")
    var command: String

    @Option(name: .long, help: "Project path (defaults to current directory)")
    var path: String?

    @Flag(name: .long, help: "Overwrite existing command if it exists")
    var force: Bool = false

    mutating func run() throws {
        let projectPath = path ?? FileManager.default.currentDirectoryPath
        let absolutePath = URL(fileURLWithPath: projectPath).standardizedFileURL.path
        let projectKey = ConfigManager.getProjectKey(for: absolutePath)

        var config = try ConfigManager.loadGlobalConfig()

        guard var projectConfig = config.projects[projectKey] else {
            print("❌ No project configuration found for path: \(absolutePath)")
            print("   Run 'build-tool init' to initialize this project")
            return
        }

        let commandName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let commandValue = command.trimmingCharacters(in: .whitespacesAndNewlines)

        if commandName.isEmpty {
            print("❌ Command name cannot be empty")
            return
        }

        if commandValue.isEmpty {
            print("❌ Command cannot be empty")
            return
        }

        if projectConfig.customCommands[commandName] != nil && !force {
            print("❌ Custom command '\(commandName)' already exists.")
            print("   Current command: \(projectConfig.customCommands[commandName]!)")
            print("   Use --force to overwrite or choose a different name")
            return
        }

        let isUpdate = projectConfig.customCommands[commandName] != nil
        projectConfig.customCommands[commandName] = commandValue
        projectConfig.lastModified = Date()
        config.projects[projectKey] = projectConfig
        config.lastUpdated = Date()

        try ConfigManager.saveGlobalConfig(config)

        if isUpdate {
            print("✅ Custom command '\(commandName)' updated successfully!")
        } else {
            print("✅ Custom command '\(commandName)' added successfully!")
        }
        print("   Command: \(commandValue)")
        print("   Project: \(projectConfig.name)")
    }
}

// MARK: - Remove Command (Custom)
struct RemoveCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "remove-command",
        abstract: "Remove a custom command from a project"
    )

    @Argument(help: "Name of the custom command to remove")
    var commandName: String

    @Option(name: .long, help: "Project path (defaults to current directory)")
    var path: String?

    mutating func run() throws {
        let projectPath = path ?? FileManager.default.currentDirectoryPath
        let absolutePath = URL(fileURLWithPath: projectPath).standardizedFileURL.path
        let projectKey = ConfigManager.getProjectKey(for: absolutePath)

        var config = try ConfigManager.loadGlobalConfig()

        guard var projectConfig = config.projects[projectKey] else {
            print("❌ No project configuration found for path: \(absolutePath)")
            print("   Run 'build-tool init' to initialize this project")
            return
        }

        guard let removedCommand = projectConfig.customCommands.removeValue(forKey: commandName)
        else {
            print("❌ Custom command '\(commandName)' not found for project '\(projectConfig.name)'")

            if !projectConfig.customCommands.isEmpty {
                print("   Available custom commands:")
                for (name, cmd) in projectConfig.customCommands.sorted(by: { $0.key < $1.key }) {
                    print("     \(name) = \(cmd)")
                }
            } else {
                print("   No custom commands configured for this project")
            }
            return
        }

        projectConfig.lastModified = Date()
        config.projects[projectKey] = projectConfig
        config.lastUpdated = Date()

        try ConfigManager.saveGlobalConfig(config)

        print("✅ Custom command '\(commandName)' removed successfully!")
        print("   Removed command: \(removedCommand)")
        print("   Project: \(projectConfig.name)")
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

            if !project.customCommands.isEmpty {
                print("  Custom Commands:")
                for (name, command) in project.customCommands.sorted(by: { $0.key < $1.key }) {
                    print("    \(name) = \(command)")
                }
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

// MARK: - Main Command
@main
struct BuildTool: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "build-tool",
        abstract: "A CLI tool for managing project builds with global configuration",
        subcommands: [
            Init.self, Build.self, Run.self, AddCommand.self, RemoveCommand.self, List.self,
            Remove.self, Config.self, Status.self,
        ],
        defaultSubcommand: List.self
    )
}
