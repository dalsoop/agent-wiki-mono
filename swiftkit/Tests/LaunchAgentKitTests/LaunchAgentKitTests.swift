import XCTest
@testable import LaunchAgentKit

final class LaunchAgentKitTests: XCTestCase {
    
    func testConfigurationDefaults() {
        let config = LaunchAgentConfiguration(
            label: "com.test.agent",
            executablePath: "/usr/bin/true"
        )
        
        XCTAssertEqual(config.label, "com.test.agent")
        XCTAssertEqual(config.executablePath, "/usr/bin/true")
        XCTAssertEqual(config.arguments, [])
        XCTAssertEqual(config.schedule, .none)
        XCTAssertEqual(config.keepAlive, false)
        XCTAssertEqual(config.processType, "Background")
        XCTAssertEqual(config.caffeinate, false)
        
        // standard paths expanding tilde
        let expandedOut = ("~/Library/Logs/host-agents/com.test.agent.stdout.log" as NSString).expandingTildeInPath
        let expandedErr = ("~/Library/Logs/host-agents/com.test.agent.stderr.log" as NSString).expandingTildeInPath
        XCTAssertEqual(config.standardOutPath, expandedOut)
        XCTAssertEqual(config.standardErrorPath, expandedErr)
    }
    
    func testGeneratePlistInterval() {
        let config = LaunchAgentConfiguration(
            label: "com.test.agent2",
            executablePath: "/usr/bin/true",
            arguments: ["--test", "<escapeme>"],
            schedule: .interval(seconds: 300)
        )
        
        let mgr = LaunchAgentManager()
        let xml = mgr.generatePlist(config: config)
        
        XCTAssertTrue(xml.contains("<key>Label</key>"))
        XCTAssertTrue(xml.contains("<string>com.test.agent2</string>"))
        XCTAssertTrue(xml.contains("<string>/usr/bin/true</string>"))
        XCTAssertTrue(xml.contains("<string>--test</string>"))
        XCTAssertTrue(xml.contains("<string>&lt;escapeme&gt;</string>"))
        
        XCTAssertTrue(xml.contains("<key>StartInterval</key>"))
        XCTAssertTrue(xml.contains("<integer>300</integer>"))
        
        XCTAssertTrue(xml.contains("<key>KeepAlive</key>"))
        XCTAssertTrue(xml.contains("<false/>"))
    }
    
    func testGeneratePlistCalendar() {
        let config = LaunchAgentConfiguration(
            label: "com.test.agent3",
            executablePath: "/usr/bin/false",
            schedule: .calendar(hour: 3, minute: 15),
            keepAlive: true,
            caffeinate: true
        )
        
        let mgr = LaunchAgentManager()
        let xml = mgr.generatePlist(config: config)
        
        XCTAssertTrue(xml.contains("<key>StartCalendarInterval</key>"))
        XCTAssertTrue(xml.contains("<key>Hour</key>"))
        XCTAssertTrue(xml.contains("<integer>3</integer>"))
        XCTAssertTrue(xml.contains("<key>Minute</key>"))
        XCTAssertTrue(xml.contains("<integer>15</integer>"))
        
        XCTAssertTrue(xml.contains("<true/>")) // KeepAlive
        XCTAssertTrue(xml.contains("<string>/usr/bin/caffeinate</string>"))
        XCTAssertTrue(xml.contains("<string>-s</string>"))
        XCTAssertTrue(xml.contains("<string>/usr/bin/false</string>"))
    }
    
    func testResolveExecutablePath() {
        let mgr = LaunchAgentManager()
        // 'ls' is typically at /bin/ls, but let's test a known one like 'true' which might be at /usr/bin/true
        let resolved = mgr.resolveExecutablePath(appName: "true", customCandidates: ["/usr/bin/true"])
        XCTAssertEqual(resolved, "/usr/bin/true")
    }
}
