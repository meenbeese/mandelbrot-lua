#include <stdint.h>
#include <math.h>

void generate_mandelbrot(uint8_t* pixels, int width, int height,
                         double centerX, double centerY, double zoom, int max_iter) {
    double baseHalfWidth = 2.5;
    double baseHalfHeight = 2.0;
    double xmin = centerX - baseHalfWidth * zoom;
    double xmax = centerX + baseHalfWidth * zoom;
    double ymin = centerY - baseHalfHeight * zoom;
    double ymax = centerY + baseHalfHeight * zoom;

    for (int x = 0; x < width; x++) {
        for (int y = 0; y < height; y++) {
            double cr = xmin + ((double) x / width) * (xmax - xmin);
            double ci = ymin + ((double) y / height) * (ymax - ymin);
            double zr = 0.0, zi = 0.0;
            int iter = 0;
            while (zr * zr + zi * zi < 4.0 && iter < max_iter) {
                double tmp = zr * zr - zi * zi + cr;
                zi = 2.0 * zr * zi + ci;
                zr = tmp;
                iter++;
            }

            double t = (double) iter / max_iter;
            int r = 9 * (1 - t) * t * t * t * 255;
            int g = 15 * (1 - t) * (1 - t) * t * t * 255;
            int b = 8.5 * (1 - t) * (1 - t) * (1 - t) * t * 255;

            int i = (y * width + x) * 4;
            pixels[i]     = r;
            pixels[i + 1] = g;
            pixels[i + 2] = b;
            pixels[i + 3] = 255;
        }
    }
}
