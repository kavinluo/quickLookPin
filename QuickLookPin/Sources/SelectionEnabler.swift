import Cocoa
import WebKit

/// 让 Quick Look 预览里的文字能被鼠标选中、能 ⌘C 复制。
///
/// 系统的 Quick Look 默认禁止选取，三种渲染方式各有各的禁法（实测结论）：
///
/// - **纯文本**（`QLTextView`，NSTextView 子类）：`isSelectable = false`，改成 true 即可。
/// - **Markdown / HTML 等**（`QLWeb2View`，WKWebView 子类）：页面被打上
///   `-webkit-user-select: none`。注意这条来自 WebKit 的 **user 级样式表**，
///   user 级的 `!important` 压得过页面级的 `!important`，所以往页面里插
///   `*{-webkit-user-select:text !important}` **没有用**（实测计算值仍是 none）。
///   可行的是 `-webkit-user-modify: read-write`：内容被当作可编辑区域，
///   选取就被放行了。副作用是文字真的可以被改，所以下面用 `beforeinput`
///   等事件把一切修改挡掉，只留下选取和复制。
/// - **PDF 等**（`NSRemoteView`）：内容在另一个进程里渲染，这里够不着，
///   能不能选取由系统的预览扩展决定，本程序无能为力。
enum SelectionEnabler {

    /// 预览是异步加载的，视图树要过一会儿才长出来，所以隔几个时间点反复施加。
    /// 注入本身是幂等的（JS 里有 `__qlpSelection` 哨兵），多跑几次没有副作用。
    private static let retryDelays: [TimeInterval] = [0.2, 0.6, 1.2, 2.0, 3.5]

    static func applyRepeatedly(to view: NSView) {
        for delay in retryDelays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak view] in
                guard let view else { return }
                apply(to: view)
            }
        }
    }

    static func apply(to view: NSView) {
        if let text = view as? NSTextView {
            text.isSelectable = true
        }
        if let web = view as? WKWebView {
            web.evaluateJavaScript(js) { result, error in
                // 只在首次注入（返回 "ok"）和出错时记一笔，重试返回 "already" 时不刷屏
                if let error {
                    NSLog("[QuickLookPin] 选取注入失败: \(error.localizedDescription)")
                } else if let result = result as? String, result == "ok" {
                    NSLog("[QuickLookPin] 选取已启用（web 预览）")
                }
            }
        }
        view.subviews.forEach(apply)
    }

    /// 打开选取 + 屏蔽一切编辑。`beforeinput` 覆盖了输入、回车、删除、拖放等
    /// 所有会改动内容的途径，`paste` / `drop` 再兜一层。
    private static let js = """
    (function () {
      if (window.__qlpSelection) { return 'already'; }
      window.__qlpSelection = true;

      var style = document.createElement('style');
      style.textContent =
        'html, body, body * {' +
        '  -webkit-user-select: text !important;' +
        '  user-select: text !important;' +
        '  -webkit-user-modify: read-write !important;' +
        '  caret-color: transparent !important;' +
        '}';
      document.documentElement.appendChild(style);
      document.documentElement.setAttribute('spellcheck', 'false');

      var block = function (e) { e.preventDefault(); };
      document.addEventListener('beforeinput', block, true);
      document.addEventListener('paste', block, true);
      document.addEventListener('drop', block, true);
      document.addEventListener('dragstart', block, true);

      return 'ok';
    })()
    """
}
