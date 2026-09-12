# Mermaid

Fenced ` ```mermaid ` blocks render in the browser. Click a diagram (or the
expand button) for a full-screen view: left-click drag to pan, mouse wheel to
zoom, Escape to close.

## Flowchart

A larger graph so zoom is useful.

```mermaid
flowchart TB
  subgraph Browser
    UI[app.js]
    M[Mermaid]
    K[KaTeX]
    UI --> M
    UI --> K
  end
  subgraph Server
    S[gfm-hotview]
    R[goldmark + GFM]
    T[file tree]
    W[live reload SSE]
    S --> R
    S --> T
    S --> W
  end
  MD[Markdown files] --> S
  IMG[Images] --> S
  UI -->|GET /api/render| S
  S -->|HTML| UI
  UI -->|GET /raw/...| IMG
```

## Sequence

```mermaid
sequenceDiagram
  actor User
  participant Browser
  participant Server
  User->>Browser: open samples/README.md
  Browser->>Server: GET /api/render
  Server-->>Browser: HTML + headings
  Browser->>Browser: mermaid.run / KaTeX
  User->>Browser: click diagram
  Browser->>User: zoom overlay
```

## Class

```mermaid
classDiagram
  class Renderer {
    +Render(src) Result
  }
  class Server {
    +handleView()
    +handleRaw()
  }
  class Result {
    HTML string
    Title string
    Headings Heading[]
  }
  Server --> Renderer : renders
  Renderer --> Result
```

## State

```mermaid
stateDiagram-v2
  [*] --> Idle
  Idle --> Loading : navigate
  Loading --> Ready : html
  Ready --> Zoom : open diagram
  Zoom --> Ready : Escape
  Ready --> Idle : close
```

## Entity relationship

```mermaid
erDiagram
  ROOT ||--o{ FILE : contains
  FILE ||--o{ HEADING : has
  FILE {
    string path
    string title
  }
  HEADING {
    int level
    string id
  }
```

## Gantt

```mermaid
gantt
  title Sample preview
  dateFormat YYYY-MM-DD
  section Docs
  Write samples           :done, a1, 2026-08-30, 1d
  Review in gfm-hotview   :active, a2, 2026-08-30, 2d
  section App
  Mermaid zoom overlay    :done, b1, 2026-08-30, 1d
```

## Pie

```mermaid
pie title Sample mix
  "Markdown pages" : 6
  "Images" : 4
  "Nested docs" : 1
```
