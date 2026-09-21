# Tonyo bundled fonts

These unmodified static TrueType fonts are bundled locally so font preferences
work offline without contacting a font provider. All three families are licensed
under the SIL Open Font License 1.1. Each family's complete copyright and license
notice is included as `OFL.txt` and packaged in the app's assets.

## Sources

- **Inter 4.1**: [official release](https://github.com/rsms/inter/releases/tag/v4.1),
  downloaded from
  `https://github.com/rsms/inter/releases/download/v4.1/Inter-4.1.zip`.
  Files are copied from `extras/ttf/`; `LICENSE.txt` is copied as `inter/OFL.txt`.
  Regular, Medium, SemiBold, and Bold cover weights 400–700.
- **Source Sans 3**: [Adobe's official repository](https://github.com/adobe-fonts/source-sans),
  release commit `87b37a2daaed80fcb8e8ccb0085c4d72ddade12e`.
  Files are copied from `TTF/`; `LICENSE.md` is copied as
  `source_sans_3/OFL.txt`. Regular, Medium, Semibold, and Bold cover
  weights 400–700.
- **Lato**: [Google Fonts' official repository](https://github.com/google/fonts/tree/main/ofl/lato),
  commit `e44c4b011a820c2cbe2fd2cfa8052037d7edb571`.
  Files and `OFL.txt` are copied from `ofl/lato/`. Regular, Medium, SemiBold,
  and Bold cover weights 400–700.

Retrieved on 2026-09-21. Binaries retain upstream font names, metadata, glyphs,
and hinting. `SHA256SUMS.txt` records hashes of the exact bundled font files.
Only the normal-style weights used by the app are included.

`System default` leaves the font family unset and uses Flutter's platform
default. It requires no bundled font file.
