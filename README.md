# Mandelbrot in Lua (Love2D)

This project is an interactive Mandelbrot set explorer built using [Love2D](https://love2d.org/).  
You can pan around and zoom into the fractal in real time with keyboard controls. It runs in full-screen and uses a hybrid renderer: a GLSL fragment shader for standard zoom levels and a precision-optimized native C library (or pure-Lua fallback) for deep zooms.

**Supported platforms:** Windows, macOS, Linux, Web

All platform builds are produced automatically by GitHub Actions — every push to `main` publishes download artifacts for macOS, Windows, Linux, and a WASM web build.

---

## Screenshots

| ![screenshot_1](assets/screenshot_1.png) | ![screenshot_2](assets/screenshot_2.png) | ![screenshot_3](assets/screenshot_3.png) |
|------------------------------------------|------------------------------------------|------------------------------------------|
| ![screenshot_4](assets/screenshot_4.png) | ![screenshot_5](assets/screenshot_5.png) | ![screenshot_6](assets/screenshot_6.png) |

---

## Controls

| Key | Action           |
|-----|------------------|
| W   | Pan up           |
| A   | Pan left         |
| S   | Pan down         |
| D   | Pan right        |
| Z   | Zoom in          |
| X   | Zoom out         |
| ESC | Quit the program |

On the web build, ESC closes the page's request to exit and clicks are used for the on-screen toggles (stats, preview, antialias).

---

## How to Run

### From a CI build

1. Go to the **Actions** tab of this repository, open the latest **Build Desktop** run.
2. Download the artifact for your platform (`mandelbrot-macos`, `mandelbrot-windows`, or `mandelbrot-linux`) and unpack it.
3. Install [Love2D](https://love2d.org/) for your platform, then run:

```sh
love mandelbrot/          # the unzipped folder containing main.lua
```

### macOS

```sh
git clone <this repo> && cd mandelbrot-lua
clang -O3 -funroll-loops -shared -o mandelbrot.dylib -fPIC mandelbrot.c
love .                    # requires love on your PATH (brew users: see note below)
```

> The Homebrew cask for Love2D is currently disabled (Gatekeeper check). Temporary workaround:
> download `love-11.x-macos.zip` from the [LÖVE GitHub releases](https://github.com/love2d/love/releases),
> run `xattr -cr love.app` after unpacking, then invoke `love.app/Contents/MacOS/love .`.

### Windows (MinGW)

```sh
gcc -O3 -funroll-loops -shared -o mandelbrot.dll -fPIC mandelbrot.c
love .
```

### Linux

```sh
gcc -O3 -funroll-loops -shared -o mandelbrot.so -fPIC mandelbrot.c
love .
```

The Lua code detects your OS and automatically loads `mandelbrot.dll`, `mandelbrot.dylib`, or `mandelbrot.so` — so the compiled library must sit next to `main.lua`.

### Web (WebAssembly)

The web build uses [2dengine's love.js](https://github.com/2dengine/love.js): the game is packed as a plain `.love` zip and served by the love.js player runtime (LÖVE 11.5, same as desktop). There is no build toolchain — a small script assembles the static bundle:

```sh
mkdir -p build/web/11.5 .webstage
cp web/index.html build/web/
cp main.lua shader.glsl .webstage/
(cd .webstage && zip -q -9 ../build/web/mandelbrot.love main.lua shader.glsl)
rm -rf .webstage
# then download player.js, style.css and the 11.5/ runtime files
# (pinned commit SHA: see .github/workflows/web.yml)
python3 -m http.server 8000 -d build/web   # must be served over HTTP, file:// will not work
```

Then open `http://localhost:8000` locally. On GitHub Actions, the **Build Web (WASM)** workflow produces a ready-to-serve `mandelbrot-web` zip artifact.

**Hosting note:** the player runtime uses `SharedArrayBuffer`/pthreads and therefore needs cross-origin isolation headers on the serving path:

```
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Embedder-Policy: require-corp
Content-Security-Policy: script-src 'self' 'wasm-unsafe-eval' 'unsafe-eval'; worker-src 'self' blob:
```

> **Note on the web build:** love.js does not include LuaJIT, so the FFI-based native library is unavailable. `main.lua` automatically falls back to a pure-Lua Mandelbrot renderer for deep zooms — same output and features (including the GLSL path for standard views), but single-threaded and slower. Enable **Preview** mode on the web for comfortable deep-zoom navigation.

---

### Compiling the C Shared Library

The desktop builds use a native C function for fast Mandelbrot rendering, compiled into a shared library sitting next to `main.lua` (`mandelbrot.dll` / `mandelbrot.so` / `mandelbrot.dylib`). Without it, the game falls back to the slower pure-Lua renderer — so compiling is strongly recommended for desktop play (see the platform commands under [How to Run](#how-to-run)).

---

## Features

- Full-screen rendering
- Real-time panning and zooming
- Dynamically adjusts iteration count for detail at high zoom
- Colored smooth shading

---

## Performance Optimizations

This project uses a **hybrid renderer** that picks the best-execution path for the current zoom level:

- **GPU path (standard views, zoom < ~10⁴):** The whole fractal — iteration loop *and* palette coloring — is computed per-pixel in a GLSL fragment shader. No CPU buffers, no texture uploads, no preview passes; results update live with the view state. This runs at display refresh rates on desktop and on the web (WebGL) alike.
- **CPU fp64 path (deep zooms ≥ ~10⁴):** GPU shaders in this GLSL level are limited to fp32, and their compilers fold away compensated "double-single" arithmetic (verified: the error-extraction terms become exactly zero on fp32-algebra-folding compilers), which turns deep views into blocky noise. Past the threshold, rendering switches to the CPU in real double precision — the native C shared library via LuaJIT FFI (desktop, multithreaded), or the pure-Lua fallback (web).

Supporting optimizations:

- **Multithreaded computation:** CPU-path rows are processed in parallel (thread count auto-detected).
- **Loop unrolling:** Enabled via -funroll-loops during compilation for faster iteration performance.
- **Dynamic max iterations:** Automatically increases with zoom level for visual detail, with clamping to avoid lag.
- **Clamped zoom precision:** Prevents zoom from becoming too small due to floating-point limits.
- **Adaptive preview mode (CPU path):** A low-resolution render is displayed while panning/zooming, then a full-resolution render kicks in 0.1 s after interaction stops (0.5 s on web).
- **Optimized pure-Lua fallback (web):** The fallback renderer inlines its per-pixel iteration loop and hoists all loop math into cached locals, minimizing interpreter overhead.
- **Heads-up display:** The stats panel shows which renderer (GPU / native C / Lua fallback) is active at the current zoom.

### Web performance

The web build uses the same split: standard views render **on the GPU** and are comparably fast to desktop. Deep zooms fall back to the pure-Lua CPU path, which runs in a Lua interpreter (love.js has no LuaJIT/FFI) — typically 50–100× slower than native C. To compensate, the web build automatically uses a coarser preview (5× downscale instead of 3×) and delays the idle full-resolution render. For the smoothest deep-zooming on the web, leave **Preview** enabled; the fullscreen render fires shortly after you stop moving.

---

## Requirements

- [Love2D](https://love2d.org/) 11.0 or later (desktop)
- C compiler (desktop — optional: without it, deep zooms use the slower pure-Lua renderer)
- Static web server with cross-origin isolation headers (web build — see [Web](#web-webassembly))
- [zip](https://linux.die.net/man/1/zip) and any HTTP client (web build scripts)

---

## License

This project is released under the MIT License.
