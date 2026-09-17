# 尖刀验证用的 Markdown

如果你看到的是**排版后的样子**（这行是粗体、下面有列表和代码块、有分隔线），
说明第三方 Quick Look 插件在自建窗口里被正常调用了 —— 方案成立。

如果你看到的是这段**原始文本**（能看见 `#` 和 `**` 这些符号），
说明扩展没被加载 —— 方案需要换路。

---

## 列表

- 第一项
- 第二项
- 第三项

## 代码块

```swift
let preview = QLPreviewView(frame: .zero, style: .normal)
preview.previewItem = url as QLPreviewItem
```

> 引用块长这样。

| 列 A | 列 B |
|------|------|
| 1    | 2    |
