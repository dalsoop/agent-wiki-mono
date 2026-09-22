import Foundation
import Testing
@testable import FleetCockpitPerspectiveKit

@Suite("StateContracts Tests — Schema Fault-Tolerance & Regression")
struct StateContractsTests {

    @Test("AgentDeckStateContract: integer agents count schema (regression test for silent decode drops)")
    func testIntegerAgentsSchema() throws {
        let json = """
        {
            "agents": 16,
            "panes": 4
        }
        """
        let data = try #require(json.data(using: .utf8))
        let decoded = try JSONDecoder().decode(AgentDeckStateContract.self, from: data)
        #expect(decoded.agentCount == 16)
        #expect(decoded.sessions.isEmpty)
    }

    @Test("AgentDeckStateContract: array agents schema (backward & forward compatibility)")
    func testArrayAgentsSchema() throws {
        let json = """
        {
            "agents": [
                {
                    "pid": 4200,
                    "tool": "claude",
                    "projectName": "fleet-cockpit",
                    "cwd": "/workspace/apps/swift-app-mono"
                }
            ]
        }
        """
        let data = try #require(json.data(using: .utf8))
        let decoded = try JSONDecoder().decode(AgentDeckStateContract.self, from: data)
        #expect(decoded.agentCount == 1)
        #expect(decoded.sessions.count == 1)
        #expect(decoded.sessions[0].pid == 4200)
        #expect(decoded.sessions[0].tool == "claude")
        #expect(decoded.sessions[0].projectName == "fleet-cockpit")
        #expect(decoded.sessions[0].cwd == "/workspace/apps/swift-app-mono")
    }

    @Test("AgentDeckStateContract: empty json resilience")
    func testEmptyJsonSchema() throws {
        let json = "{}"
        let data = try #require(json.data(using: .utf8))
        let decoded = try JSONDecoder().decode(AgentDeckStateContract.self, from: data)
        #expect(decoded.agentCount == 0)
        #expect(decoded.sessions.isEmpty)
    }

    @Test("AwoStateContract: inner state and outer fallback parsing")
    func testAwoStateParsing() throws {
        let json = """
        {
            "state": {
                "activeJobCount": 2,
                "generatedAt": 1757080000.0,
                "jobs": [
                    {
                        "id": "job-alpha-1234",
                        "title": "spawn: fleet-dock lint",
                        "state": "running",
                        "since": 1757079900.0,
                        "tenantID": "tenant:personal",
                        "roomID": "79FDF732"
                    }
                ]
            }
        }
        """
        let data = try #require(json.data(using: .utf8))
        let decoded = try JSONDecoder().decode(AwoStateContract.self, from: data)
        #expect(decoded.allJobs.count == 1)
        #expect(decoded.allJobs[0].id == "job-alpha-1234")
        #expect(decoded.allJobs[0].title == "spawn: fleet-dock lint")
        #expect(decoded.allJobs[0].state == "running")
        #expect(decoded.allJobs[0].tenantID == "tenant:personal")
        #expect(decoded.allJobs[0].roomID == "79FDF732")
    }
}
