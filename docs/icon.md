# AIUsage icon

Master artwork: [`Resources/AppIcon.png`](../Resources/AppIcon.png), 1254 × 1254 RGBA PNG. Generated with the built-in ImageGen tool. The transparent canvas and blue tile identify AIUsage in Finder, the installer, and the About panel.

`scripts/build-icon.sh` converts the artwork into 16, 32, 128, 256, and 512 point icons at standard and Retina resolutions, then packages `build/assets/AppIcon.icns` with Apple's `iconutil`. The app and disk image use that icon. These files are generated from the checked-in PNG and do not require image generation during builds.

Generation prompt:

> Use case: logo-brand. Asset type: final production macOS application icon for AIUsage, a small menu bar utility for Claude Code and Codex quota and token usage. Create one polished, distinctive icon at 1024 x 1024 with real alpha transparency outside its rounded-square macOS icon tile. Centered, front-on, no perspective. A deep midnight-indigo rounded square with generous continuous corners, subtle dimensional bevel and restrained soft shadow. Its central symbol is a bold, beautifully balanced usage gauge: three thick rounded vertical bars rising left to right, in luminous turquoise, mint, and warm amber, enclosed by a clean incomplete circular gauge arc with a tiny bright indicator at the upper right. Very simple geometric silhouette, precise spacing, strong legibility at 32px, professional native Mac utility quality. The symbol fills roughly 60 percent of the tile, generous safe padding. Tile occupies about 84 percent of the square canvas. No text, no letters, no numbers, no brand marks, no robot, no sparkle or generic AI star, no extra scenery, no mockup, no visible background. Deliver only the single icon image, transparent outside the tile.
