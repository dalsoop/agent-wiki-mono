import Foundation

/// HTML chrome for locally rendered product pages. Kept out of `LibraryController`
/// so download/install IO is not mixed with presentation strings.
enum LibraryRenderChrome {
    static let emptyDetailHTML = "<article></article>"
    static let darkCss =
        "@media (prefers-color-scheme: dark){:root{color-scheme:dark}body{background:#1d1d1f;color:#ddd}}"
    static let thumbnailLayoutCss =
        "html,body{margin:0;height:100%;overflow:hidden;background:transparent}#thumbroot{transform-origin:top left}"
    static let thumbnailFitJavaScript = [
        "(function(){function f(){var el=document.getElementById('thumbroot');if(!el)return;",
        "el.style.transform='none';var w=el.scrollWidth,h=el.scrollHeight;if(!w||!h)return;",
        "var s=Math.min(window.innerWidth/w,window.innerHeight/h,1);",
        "var x=(window.innerWidth-w*s)/2,y=(window.innerHeight-h*s)/2;",
        "el.style.transform='translate('+x+'px,'+y+'px) scale('+s+')';}",
        "window.addEventListener('load',f);window.addEventListener('resize',f);setTimeout(f,60);})();",
    ].joined()
}
