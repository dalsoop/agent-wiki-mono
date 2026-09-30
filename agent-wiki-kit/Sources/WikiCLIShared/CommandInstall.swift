import Foundation

/// `install` 하위 명령 — PATH 에 아무것도 쓰지 않는다.
/// PATH 명령(`/opt/homebrew/bin` 등) 연결의 유일한 쓰기 주체는 배포 도구(`app-build-manager ship <앱>`)다
/// (위키 abb1f223, 한 대상에 쓰는 주체는 하나). 옛 호출자가 깨지지 않도록 안내만 하고 0 으로 끝난다.
public func runInstall(arguments: [String]) {
    print("install: PATH 연결은 배포(`app-build-manager ship <앱>`)가 한다. 이 명령은 아무것도 쓰지 않는다.") // allow:debug
}
