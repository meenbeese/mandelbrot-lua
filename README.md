# Mandelbrot in Lua (Love2D)

This project is an interactive Mandelbrot set explorer built using [Love2D](https://love2d.org/).  
You can pan around and zoom into the fractal in real time with keyboard controls. It runs in full-screen and uses a performance-optimized render buffer for smooth zooming.

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
   Create a folder named `mandelbrot` (or any name you like), and place your `main.lua` file inside it.

3. **Run the project:**  
   - **Option 1:** Drag the folder onto the Love2D executable.
   - **Option 2:** From a terminal, run:
     ```sh
     love mandelbrot/
     ```

---

## Features

- Full-screen rendering
- Real-time panning and zooming
- Dynamically adjusts iteration count for detail at high zoom
- Colored smooth shading
- Fast performance using a lower-resolution render buffer scaled to full screen

---

## Requirements

- [Love2D](https://love2d.org/) 11.0 or later

---

## License

This project is released under the MIT License.
