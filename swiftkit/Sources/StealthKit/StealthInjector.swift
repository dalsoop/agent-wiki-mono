import Foundation

/// 프로필 기반 anti-fingerprint JS 를 CDP Page.addScriptToEvaluateOnNewDocument 로 주입.
///
/// 페이지 로드 전에 실행돼 모든 JS 실행 컨텍스트에서 유효하다.
/// 세션 내내 같은 값을 반환해야 하므로 프로필에서 결정적으로 생성.
public enum StealthInjector {

    /// 문자열을 JS 문자열 리터럴로 안전하게 변환 (injection 방지).
    /// String 은 macOS 14 미만에서 JSONSerialization top-level 이 아니고,
    /// 실패 시 NSInvalidArgumentException 이라 try? 로 잡을 수 없다.
    private static func jsString(_ value: String) -> String {
        var escaped = value
        escaped = escaped.replacingOccurrences(of: "\\", with: "\\\\")
        escaped = escaped.replacingOccurrences(of: "\"", with: "\\\"")
        escaped = escaped.replacingOccurrences(of: "\n", with: "\\n")
        escaped = escaped.replacingOccurrences(of: "\r", with: "\\r")
        escaped = escaped.replacingOccurrences(of: "\t", with: "\\t")
        escaped = escaped.replacingOccurrences(of: "\u{2028}", with: "\\u2028")
        escaped = escaped.replacingOccurrences(of: "\u{2029}", with: "\\u2029")
        return "\"\(escaped)\""
    }

    private static func navigatorJS(for profile: StealthProfile) -> String {
        let langArray = "[" + profile.languages.map { jsString($0) }.joined(separator: ",") + "]"
        return """
            const navOverrides = {
                platform: \(jsString(profile.platform)),
                hardwareConcurrency: \(Int(profile.hardwareConcurrency)),
                deviceMemory: \(Int(profile.deviceMemory)),
                languages: \(langArray),
            };
            function defineNavGetter(prop, value) {
                try {
                    Object.defineProperty(Navigator.prototype, prop, {
                        get: () => value, configurable: true,
                    });
                } catch (e) {
                    try {
                        Object.defineProperty(navigator, prop, {
                            get: () => value, configurable: true,
                        });
                    } catch (e2) {}
                }
            }
            defineNavGetter('platform', navOverrides.platform);
            defineNavGetter('hardwareConcurrency', navOverrides.hardwareConcurrency);
            defineNavGetter('deviceMemory', navOverrides.deviceMemory);
            defineNavGetter('languages', navOverrides.languages);
        """
    }

    private static func screenJS(for profile: StealthProfile) -> String {
        return """
            function defineScreenGetter(prop, value) {
                try {
                    Object.defineProperty(Screen.prototype, prop, {
                        get: () => value, configurable: true,
                    });
                } catch (e) {}
            }
            defineScreenGetter('width', \(Int(profile.screenWidth)));
            defineScreenGetter('height', \(Int(profile.screenHeight)));
            defineScreenGetter('colorDepth', \(Int(profile.colorDepth)));
            defineScreenGetter('pixelDepth', \(Int(profile.colorDepth)));
        """
    }

    private static func canvasJS(for profile: StealthProfile) -> String {
        return """
            const origToDataURL = HTMLCanvasElement.prototype.toDataURL;
            const origToBlob = HTMLCanvasElement.prototype.toBlob;
            const seed = \(Int(profile.canvasNoiseSeed));
            function noise(ctx, w, h) {
                if (seed === 0) return;
                const imageData = ctx.getImageData(0, 0, Math.min(w, 4), Math.min(h, 4));
                for (let i = 0; i < imageData.data.length; i += 4) {
                    imageData.data[i] = (imageData.data[i] + (seed * (i + 1) % 3) - 1) & 0xFF;
                }
                ctx.putImageData(imageData, 0, 0);
            }
            HTMLCanvasElement.prototype.toDataURL = function() {
                const ctx = this.getContext('2d');
                if (ctx) noise(ctx, this.width, this.height);
                return origToDataURL.apply(this, arguments);
            };
            HTMLCanvasElement.prototype.toBlob = function() {
                const ctx = this.getContext('2d');
                if (ctx) noise(ctx, this.width, this.height);
                return origToBlob.apply(this, arguments);
            };
        """
    }

    private static func webglJS(for profile: StealthProfile) -> String {
        return """
            const origGetParam = WebGLRenderingContext.prototype.getParameter;
            WebGLRenderingContext.prototype.getParameter = function(param) {
                const ext = this.getExtension('WEBGL_debug_renderer_info');
                if (ext && param === ext.UNMASKED_VENDOR_WEBGL) return \(jsString(profile.webglVendor));
                if (ext && param === ext.UNMASKED_RENDERER_WEBGL) return \(jsString(profile.webglRenderer));
                return origGetParam.apply(this, arguments);
            };
            if (typeof WebGL2RenderingContext !== 'undefined') {
                const origGetParam2 = WebGL2RenderingContext.prototype.getParameter;
                WebGL2RenderingContext.prototype.getParameter = function(param) {
                    const ext = this.getExtension('WEBGL_debug_renderer_info');
                    if (ext && param === ext.UNMASKED_VENDOR_WEBGL) return \(jsString(profile.webglVendor));
                    if (ext && param === ext.UNMASKED_RENDERER_WEBGL) return \(jsString(profile.webglRenderer));
                    return origGetParam2.apply(this, arguments);
                };
            }
        """
    }

    private static func timezoneJS(for profile: StealthProfile) -> String {
        return """
            const origDTF = Intl.DateTimeFormat;
            const tz = \(jsString(profile.timezone));
            Intl.DateTimeFormat = function(locale, opts) {
                opts = opts || {};
                if (!opts.timeZone) opts.timeZone = tz;
                return new origDTF(locale, opts);
            };
            Object.setPrototypeOf(Intl.DateTimeFormat, origDTF);
            Intl.DateTimeFormat.prototype = origDTF.prototype;
        """
    }

    /// 프로필을 anti-fingerprint JS 스크립트로 변환.
    public static func script(for profile: StealthProfile) -> String {
        """
        // Anti-fingerprint injection (profile: \(jsString(profile.id)))
        (() => {
            // Navigator overrides — instance-level redefine 는 브라우저가 막지만
            // Navigator.prototype 은 configurable 이라 redefine 가능
            // (puppeteer-stealth / hide-my-fingerprint 실측 패턴).
            \(navigatorJS(for: profile))
            // Screen overrides — Screen.prototype 기반
            \(screenJS(for: profile))
            // Canvas noise — deterministic per profile
            \(canvasJS(for: profile))
            // WebGL overrides
            \(webglJS(for: profile))
            // Timezone override
            \(timezoneJS(for: profile))
            // webdriver / chrome 흔적 제거 — prototype-level
            try { delete Navigator.prototype.webdriver; } catch (e) {}
            if (!window.chrome) window.chrome = {};
            window.chrome.runtime = {id: undefined};
        })();
        """
    }
}
