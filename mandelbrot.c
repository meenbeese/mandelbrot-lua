#include <stdint.h>
#include <math.h>

#if defined(_WIN32)
    #include <windows.h>
    #define THREAD_RETURN DWORD WINAPI
    #define THREAD_HANDLE HANDLE
#else
    #include <pthread.h>
    #define THREAD_RETURN void*
    #define THREAD_HANDLE pthread_t
#endif

#define COLOR_TABLE_SIZE 1024

typedef struct {
    uint8_t r, g, b;
} Color;

static Color color_table[COLOR_TABLE_SIZE];

void init_color_table(int max_iter) {
    for (int i = 0; i < COLOR_TABLE_SIZE; i++) {
        double t = (double)i / (COLOR_TABLE_SIZE - 1);
        uint8_t r = (uint8_t)(9 * (1 - t) * t * t * t * 255);
        uint8_t g = (uint8_t)(15 * (1 - t) * (1 - t) * t * t * 255);
        uint8_t b = (uint8_t)(8.5 * (1 - t) * (1 - t) * (1 - t) * t * 255);
        color_table[i].r = r;
        color_table[i].g = g;
        color_table[i].b = b;
    }
}

typedef struct {
    uint8_t* pixels;
    int width;
    int height;
    double xmin;
    double xmax;
    double ymin;
    double ymax;
    int max_iter;
    int y_start;
    int y_end;
} MandelbrotJob;

static void compute_row_range(MandelbrotJob* job) {
    for (int y = job->y_start; y < job->y_end; y++) {
        for (int x = 0; x < job->width; x++) {
            double cr = job->xmin + (x / (double)job->width) * (job->xmax - job->xmin);
            double ci = job->ymin + (y / (double)job->height) * (job->ymax - job->ymin);

            double zr = 0.0, zi = 0.0;
            double zr2 = 0.0, zi2 = 0.0;
            int iter = 0;
            while (zr2 + zi2 < 4.0 && iter < job->max_iter) {
                zi = 2.0 * zr * zi + ci;
                zr = zr2 - zi2 + cr;

                zr2 = zr * zr;
                zi2 = zi * zi;
                iter++;
            }

            int color_index = (int)(((double)iter / job->max_iter) * (COLOR_TABLE_SIZE - 1));
            Color color = color_table[color_index];

            uint8_t r = color.r;
            uint8_t g = color.g;
            uint8_t b = color.b;

            int i = (y * job->width + x) * 4;
            job->pixels[i + 0] = r;
            job->pixels[i + 1] = g;
            job->pixels[i + 2] = b;
            job->pixels[i + 3] = 255;
        }
    }
}

#if defined(_WIN32)
THREAD_RETURN thread_func(LPVOID arg) {
    compute_row_range((MandelbrotJob*)arg);
    return 0;
}
#else
THREAD_RETURN thread_func(void* arg) {
    compute_row_range((MandelbrotJob*)arg);
    return NULL;
}
#endif

int get_thread_count() {
#if defined(_WIN32)
    SYSTEM_INFO sysinfo;
    GetSystemInfo(&sysinfo);
    return sysinfo.dwNumberOfProcessors;
#else
    return (int)sysconf(_SC_NPROCESSORS_ONLN);
#endif
}

void generate_mandelbrot(uint8_t* pixels, int width, int height,
                         double centerX, double centerY, double zoom,
                         int max_iter, int threads) {
    init_color_table(max_iter);

    double baseHalfWidth = 2.5;
    double baseHalfHeight = 2.0;
    double scale = zoom;
    double xmin = centerX - baseHalfWidth * scale;
    double xmax = centerX + baseHalfWidth * scale;
    double ymin = centerY - baseHalfHeight * scale;
    double ymax = centerY + baseHalfHeight * scale;

    MandelbrotJob* jobs = (MandelbrotJob*)malloc(sizeof(MandelbrotJob) * threads);
    THREAD_HANDLE* handles = (THREAD_HANDLE*)malloc(sizeof(THREAD_HANDLE) * threads);

    int slice = height / threads;
    for (int i = 0; i < threads; i++) {
        jobs[i].pixels = pixels;
        jobs[i].width = width;
        jobs[i].height = height;
        jobs[i].xmin = xmin;
        jobs[i].xmax = xmax;
        jobs[i].ymin = ymin;
        jobs[i].ymax = ymax;
        jobs[i].max_iter = max_iter;
        jobs[i].y_start = i * slice;
        jobs[i].y_end = (i == threads - 1) ? height : (i + 1) * slice;

#if defined(_WIN32)
        handles[i] = CreateThread(NULL, 0, thread_func, &jobs[i], 0, NULL);
#else
        pthread_create(&handles[i], NULL, thread_func, &jobs[i]);
#endif
    }

    for (int i = 0; i < threads; i++) {
#if defined(_WIN32)
        WaitForSingleObject(handles[i], INFINITE);
        CloseHandle(handles[i]);
#else
        pthread_join(handles[i], NULL);
#endif
    }

    free(jobs);
    free(handles);
}
