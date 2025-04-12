# Mandelbrot in Lua (Love2D)

This project is an interactive Mandelbrot set explorer built using [Love2D](https://love2d.org/).  
You can pan around and zoom into the fractal in real time with keyboard controls. It runs in full-screen and uses a performance-optimized native C library to compute the fractal efficiently.

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

---

## How to Run

1. **Install Love2D:**  
   Download and install Love2D from https://love2d.org/ for your platform.

2. **Set up project folder:**  
   Create a folder named `mandelbrot` (or any name you like), and place your `main.lua` file inside it, along with the compiled C shared library (`mandelbrot.dll`, `mandelbrot.so`, or `mandelbrot.dylib` depending on your OS).

3. **Run the project:**  
   - **Option 1:** Drag the folder onto the Love2D executable.
   - **Option 2:** From a terminal, run:
     ```sh
     love mandelbrot/
     ```

---

## Compiling the C Shared Library

The project uses a native C function to speed up Mandelbrot rendering. You must compile the `mandelbrot.c` file into a shared library:

### On Windows (MinGW or MSVC):

```sh
gcc -O3 -funroll-loops -shared -o mandelbrot.dll -fPIC mandelbrot.c
```

### On Linux

```sh
gcc -O3 -funroll-loops -shared -o mandelbrot.so -fPIC mandelbrot.c
```

### On macOS

```sh
gcc -O3 -funroll-loops -shared -o mandelbrot.dylib -fPIC mandelbrot.c
```

Make sure the resulting file is named exactly:

- `mandelbrot.dll` on Windows
- `mandelbrot.so` on Linux
- `mandelbrot.dylib` on macOS

The Lua code will detect your OS and load the appropriate file automatically.

---

## Features

- Full-screen rendering
- Real-time panning and zooming
- Dynamically adjusts iteration count for detail at high zoom
- Colored smooth shading

---

## Performance Optimizations

This project includes several key optimizations to ensure smooth, real-time Mandelbrot rendering:

- **Native C backend:** All Mandelbrot calculations are done in a compiled C shared library via LuaJIT FFI.
- **Multithreaded computation:** Rows are processed in parallel using multiple threads (auto-detected at runtime).
- **Loop unrolling:** Enabled via -funroll-loops during compilation for faster iteration performance.
- **Cached bounds:** xmin, xmax, ymin, and ymax are calculated only when zoom or pan occurs.
- **Dynamic max iterations:** Automatically increases with zoom level for visual detail, with clamping to avoid lag.
- **Clamped zoom precision:** Prevents zoom from becoming too small due to floating-point limits.
- **GLSL fragment shader coloring:** Coloring is handled entirely on the GPU for smooth gradients and zero CPU cost.
- **GPU-accelerated texture rendering:** Fractal data is uploaded to a texture and drawn in one pass for efficiency.

---

## Requirements

- [Love2D](https://love2d.org/) 11.0 or later
- C compiler

---

## License

This project is released under the MIT License.
