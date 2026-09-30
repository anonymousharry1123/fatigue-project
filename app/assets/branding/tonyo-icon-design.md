# Tonyo app icon

[Selected source](tonyo-icon-source.png) · [Launcher master](tonyo-app-icon.png)

The user-selected icon is a blue and turquoise circular wave mark on white.
The original attachment is preserved as `tonyo-icon-source.png`. The built-in
image generation tool prepared the opaque square master in edit mode by filling
the transparent exterior with white and cleaning the outer tile edge.

## Installed assets

The launcher master replaces the default Flutter icons in the existing Android,
iOS, macOS, Windows, and web asset locations. Existing manifest and asset catalog
references are retained.

- Android: 48, 72, 96, 144, and 192 px launcher PNGs.
- iOS: all 15 PNGs referenced by the AppIcon catalog, including the opaque
  1024 px App Store icon. The operating system supplies the corner mask.
- macOS: 16–1024 px PNGs with a rounded white tile and transparent outer margin
  for the existing desktop asset catalog.
- Windows: ICO containing 16, 24, 32, 48, 64, 128, and 256 px PNG frames.
- Web: 192 and 512 px standard and maskable icons, plus a 32 px favicon.

Platform sizes were exported with Core Graphics and ImageIO in sRGB. Mobile and
web PNGs are opaque. Desktop exports use a rounded tile inset by 1/16 of the
canvas on each side. Rebuild and reinstall the app to update launcher caches.

## Master preparation prompt

Prepare the supplied, user-selected Tonyo icon for launcher export. Preserve the blue upper semicircle, turquoise lower semicircle, both flowing white wave ribbons, their exact curves, colors, gradients, proportions, placement, and orientation. Do not redraw, reinterpret, simplify, rotate, or add anything to the symbol. Change ONLY the exterior background: replace the transparent exterior around the rounded white tile with opaque white, and remove the rough white outer fringe by making the entire canvas an uninterrupted clean WHITE square. The existing rounded-tile boundary should disappear into this same white background. Keep the symbol the same size and position within the square. No border, no text, no shadow, no extra elements. Output a flat, opaque square app-icon master, with white covering all four corners and edges.
