# Code

Fenced blocks get syntax highlighting (Chroma, GitHub style) and a copy button
on hover.

## Go

```go
package render

func (r *Renderer) Render(src []byte) (Result, error) {
	src = stripFrontmatter(src)
	doc := r.md.Parser().Parse(text.NewReader(src))
	var buf bytes.Buffer
	if err := r.md.Renderer().Render(&buf, src, doc); err != nil {
		return Result{}, err
	}
	return Result{HTML: buf.String()}, nil
}
```

## Python

```python
def fibonacci(n: int) -> list[int]:
    a, b = 0, 1
    out = []
    for _ in range(n):
        out.append(a)
        a, b = b, a + b
    return out
```

## JavaScript

```javascript
function navigate(path) {
  fetch("/api/render?path=" + encodeURIComponent(path))
    .then(function (r) { return r.json(); })
    .then(function (data) {
      contentEl.innerHTML = data.html;
      enhanceContent();
    });
}
```

## Shell and JSON

```bash
go run . samples
```

```json
{
  "server": {
    "host": "127.0.0.1",
    "port": 6419
  }
}
```

Mermaid fenced blocks are diagrams, not copyable source — see [mermaid.md](mermaid.md).
