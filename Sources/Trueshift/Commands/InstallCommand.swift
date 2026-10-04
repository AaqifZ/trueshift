// InstallCommand.swift
// Install/uninstall launchd agent for automatic scheduling

import ArgumentParser
import Foundation
import TrueshiftCore

struct InstallCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "install",
        abstract: "Install launchd agent for automatic schedule updates"
    )

    func run() throws {
        let agentDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents")
        let plistPath = agentDir.appendingPathComponent("com.trueshift.agent.plist")

        // Find the trueshift binary location
        let trueshiftPath = ProcessInfo.processInfo.arguments[0]

        // Create plist content
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>com.trueshift.agent</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(trueshiftPath)</string>
                <string>auto</string>
            </array>
            <key>StartInterval</key>
            <integer>300</integer>
            <key>RunAtLoad</key>
            <true/>
            <key>StandardOutPath</key>
            <string>/tmp/trueshift.log</string>
            <key>StandardErrorPath</key>
            <string>/tmp/trueshift.error.log</string>
        </dict>
        </plist>
        """

        // Ensure directory exists
        try FileManager.default.createDirectory(
            at: agentDir,
            withIntermediateDirectories: true
        )

        // Write plist
        try plist.write(to: plistPath, atomically: true, encoding: .utf8)

        // Load the agent
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["load", plistPath.path]
        try process.run()
        process.waitUntilExit()

        if process.terminationStatus == 0 {
            print("✓ Trueshift agent installed")
            print("  Running every 5 minutes")
            print("  Logs: /tmp/trueshift.log")
            print("")
            print("To uninstall: trueshift uninstall")
        } else {
            throw RuntimeError("Failed to load launchd agent")
        }
    }
}

struct UninstallCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "uninstall",
        abstract: "Remove launchd agent"
    )

    func run() throws {
        let plistPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/com.trueshift.agent.plist")

        guard FileManager.default.fileExists(atPath: plistPath.path) else {
            print("Trueshift agent is not installed")
            return
        }

        // Unload the agent
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["unload", plistPath.path]
        try process.run()
        process.waitUntilExit()

        // Remove plist
        try FileManager.default.removeItem(at: plistPath)

        // Restore display defaults
        DisplayController.reset()

        print("✓ Trueshift agent uninstalled")
        print("  Display restored to defaults")
    }
}
