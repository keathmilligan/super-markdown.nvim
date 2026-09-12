# Images

Relative image paths are rewritten to `/raw/…` so they load from the served
tree. Absolute `https://` and `data:` URLs are left alone.

Click an image (or its expand button) for a full-screen view: left-click drag
to pan, mouse wheel to zoom, Escape to close. A linked image still follows the
link on click; use the expand button to zoom instead.

## SVG

![gfm-hotview logo](images/logo.svg)

The logo is an SVG next to this page (`samples/images/logo.svg`).

![Markdown to browser pipeline](images/architecture.svg)

## Illustration

![Landscape illustration with sun, hills, and a tree](images/landscape.svg)

## Raster

A generated PNG gradient:

![Blue gradient raster image](images/gradient.png)

## Linked image

[![Logo linking to nested page](images/logo.svg)](nested/linked.md)

Click the logo to follow a relative markdown link into [nested/linked.md](nested/linked.md).
