import XCTest
@testable import SecretMaskKit

final class SecretMaskKitTests: XCTestCase {

    // MARK: - 규칙 1: 값 형태 토큰 (--token, --api-key, --password, --secret, -p 뒤 값)
    func testValueFlagTokens() {
        // 공백 분리
        XCTAssertEqual(SecretMask.command("mycli --token my-secret-token-123"), "mycli --token ***")
        XCTAssertEqual(SecretMask.command("mycli --api-key apikey-value-456"), "mycli --api-key ***")
        XCTAssertEqual(SecretMask.command("mycli --password pass-word-789"), "mycli --password ***")
        XCTAssertEqual(SecretMask.command("mycli --secret very-secret-value"), "mycli --secret ***")
        XCTAssertEqual(SecretMask.command("mysql -u root -p mypassword db"), "mysql -u root -p *** db")

        // = 결합
        XCTAssertEqual(SecretMask.command("mycli --token=my-secret-token-123"), "mycli --token=***")
        XCTAssertEqual(SecretMask.command("mycli --api-key=\"spaced secret key\""), "mycli --api-key=***")
        XCTAssertEqual(SecretMask.command("mycli --password='quoted-pass'"), "mycli --password=***")
        XCTAssertEqual(SecretMask.command("mycli --secret=very-secret"), "mycli --secret=***")
        XCTAssertEqual(SecretMask.command("mysql -p=mypassword"), "mysql -p=***")
    }

    // MARK: - 규칙 2: KEY=VALUE 에서 KEY 가 TOKEN|SECRET|PASSWORD|KEY|AUTH 를 포함
    func testKeyValueSensitive() {
        XCTAssertEqual(SecretMask.command("export AUTH_TOKEN=secret_val_123"), "export AUTH_TOKEN=***")
        XCTAssertEqual(SecretMask.command("MY_SECRET=\"top_secret_val\""), "MY_SECRET=***")
        XCTAssertEqual(SecretMask.command("DATABASE_PASSWORD=plain_pass"), "DATABASE_PASSWORD=***")
        XCTAssertEqual(SecretMask.command("API_KEY=key12345678"), "API_KEY=***")
        XCTAssertEqual(SecretMask.command("APP_AUTH='bearer_token'"), "APP_AUTH=***")
    }

    // MARK: - 규칙 3: Authorization: 헤더
    func testAuthorizationHeader() {
        XCTAssertEqual(
            SecretMask.command("curl -H \"Authorization: Bearer my-secret-jwt-token\" https://api.example.com"),
            "curl -H \"Authorization: ***\" https://api.example.com"
        )
        XCTAssertEqual(
            SecretMask.command("curl -H 'Authorization: Basic dXNlcjpwYXNz' https://api.example.com"),
            "curl -H 'Authorization: ***' https://api.example.com"
        )
        XCTAssertEqual(
            SecretMask.command("curl -H Authorization:Bearer-token-xyz https://api.example.com"),
            "curl -H Authorization: *** https://api.example.com"
        )
    }

    // MARK: - 규칙 4: sk-, ghp_, glpat-, xoxb- 접두 토큰
    func testPrefixTokens() {
        XCTAssertEqual(SecretMask.command("echo sk-proj-1234567890abcdef"), "echo ***")
        XCTAssertEqual(SecretMask.command("git clone https://github.com token: ghp_1234567890abcdef123456"), "git clone https://github.com token: ***")
        XCTAssertEqual(SecretMask.command("curl https://gitlab.com -H glpat-abcdef1234567890"), "curl https://gitlab.com -H ***")
        XCTAssertEqual(SecretMask.command("slack-post --bot xoxb-12345678-abcdefgh"), "slack-post --bot ***")
    }

    // MARK: - 규칙 5: URL 의 user:pass@
    func testURLUserInfo() {
        XCTAssertEqual(
            SecretMask.command("git clone https://alice:supersecret@github.com/org/repo.git"), // allow:secret
            "git clone https://alice:***@github.com/org/repo.git"
        )
        XCTAssertEqual(
            SecretMask.command("postgres://admin:dbpassword123@localhost:5432/mydb"), // allow:secret
            "postgres://admin:***@localhost:5432/mydb"
        )
    }

    // MARK: - SecretMask.arguments(_ argv: [String])
    func testArguments() {
        let rawArgv = [
            "curl",
            "-H", "Authorization: Bearer secret-token-xyz",
            "--token", "secret123",
            "--api-key=mykey456",
            "-p", "pass789",
            "API_KEY=envsecret",
            "https://user:pass@example.com/api",
            "ghp_0123456789abcdef",
            "--verbose"
        ]
        let expected = [
            "curl",
            "-H", "Authorization: ***",
            "--token", "***",
            "--api-key=***",
            "-p", "***",
            "API_KEY=***",
            "https://user:***@example.com/api",
            "***",
            "--verbose"
        ]
        XCTAssertEqual(SecretMask.arguments(rawArgv), expected)
    }

    // MARK: - SecretMask.headers(_ dict: [String:String])
    func testHeaders() {
        let rawHeaders = [
            "Authorization": "Bearer secret-token-value",
            "X-API-KEY": "my-api-key-val",
            "Custom-Secret": "secret-payload",
            "Content-Type": "application/json",
            "User-Agent": "MyClient/1.0",
            "X-Token-Ref": "ghp_1234567890abcdef"
        ]
        let masked = SecretMask.headers(rawHeaders)
        XCTAssertEqual(masked["Authorization"], "***")
        XCTAssertEqual(masked["X-API-KEY"], "***")
        XCTAssertEqual(masked["Custom-Secret"], "***")
        XCTAssertEqual(masked["Content-Type"], "application/json")
        XCTAssertEqual(masked["User-Agent"], "MyClient/1.0")
        XCTAssertEqual(masked["X-Token-Ref"], "***")
    }

    // MARK: - 마스킹 대상이 아닌 일반 명령 변형 방지 (2건 이상)
    func testNonMaskingCommandsUnchanged() {
        // 일반 명령 1
        let cmd1 = "swift test --package-path swiftkit --filter SecretMaskKit"
        XCTAssertEqual(SecretMask.command(cmd1), cmd1)

        // 일반 명령 2
        let cmd2 = "git commit -m \"feat: add shiny feature\" --author \"Author <author@example.com>\""
        XCTAssertEqual(SecretMask.command(cmd2), cmd2)

        // 일반 명령 3
        let cmd3 = "ls -la /tmp/workspace && echo hello"
        XCTAssertEqual(SecretMask.command(cmd3), cmd3)

        // 일반 환경변수
        let cmd4 = "PATH=/usr/bin:/bin USER=jeonghan HOME=/Users/jeonghan"
        XCTAssertEqual(SecretMask.command(cmd4), cmd4)
    }
}
