# Sinsajo Docs Site

Landing + documentation for [Sinsajo](https://github.com/lutgaru/Sinsajo) built with [Astro Starlight](https://starlight.astro.build). Deployed to **GitHub Pages** together with the Flutter Web app.

## Architecture

```
https://lutgaru.github.io/Sinsajo/       -> Astro (this site, docs + landing)
https://lutgaru.github.io/Sinsajo/app/   -> Flutter Web (sinsajo_client/build/web)
https://github.com/lutgaru/Sinsajo/releases -> APKs
```

Docs-site builds to `dist/`. Flutter Web is merged into `dist/app/` during the Pages deploy workflow.

## Local dev

```bash
cd docs-site
npm ci
npm run dev
# -> http://localhost:4321/Sinsajo/
```

Preview production build:

```bash
npm run build
npm run preview
```

With Flutter Web locally (optional):

```bash
# build flutter web first
cd ../sinsajo_client
flutter build web --base-href /Sinsajo/app/

# then build docs and merge
cd ../docs-site
npm run build
# PowerShell: Copy-Item -Recurse -Force ../sinsajo_client/build/web/* dist/app/
# Bash: cp -r ../sinsajo_client/build/web/* dist/app/
npm run preview
```

## Configuration

- `astro.config.mjs` → `site: https://lutgaru.github.io`, `base: /Sinsajo/` (for `github.io` Pages). For a custom domain, set `base: '/'` and add `public/CNAME`.
- Sidebar & i18n in `astro.config.mjs`.
- Styles in `src/styles/custom.css` (brand orange `#ff8000`).

## Typography

Fonts are **self-hosted** via Fontsource so the site renders the same on Linux, Windows,
macOS, Android and iOS — the OS default stack otherwise falls back to DejaVu Sans on
Linux (much wider/rougher than Segoe UI on Windows). No Google Fonts CDN is involved,
so the site stays offline-friendly and privacy-preserving.

- Body/headings: **Inter Variable** (`@fontsource-variable/inter`, optical-size axis).
- Code/UI mono: **JetBrains Mono Variable** (`@fontsource-variable/jetbrains-mono`).
- Loaded in `astro.config.mjs` → `starlight.customCss`; mapped to Starlight's
  `--sl-font` / `--sl-font-mono` variables in `src/styles/custom.css`.
- Only the Latin subsets (~190 KB total) are fetched for English/Spanish pages;
  the remaining subset files are emitted but requested on demand by `unicode-range`.

## Content

- Landing: `src/content/docs/index.mdx` (splash template)
- Docs: `src/content/docs/{intro,guides/**,reference/**}` — edit markdown/mdx, sidebar autogenerates.

## Deploy

Push to `master` or publish a release → `.github/workflows/docs.yml` builds Astro + Flutter Web and deploys to Pages. No manual `gh-pages` branch.

See also root `readme.md` for project overview.
