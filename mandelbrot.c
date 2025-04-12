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

typedef struct {
    uint8_t* pixels;
    int width;
    int height;
    double centerX;
    double centerY;
    double zoom;
    int max_iter;
    int y_start;
    int y_end;
} MandelbrotJob;

static void compute_row_range(MandelbrotJob* job) {
    double baseHalfWidth = 2.5;
    double baseHalfHeight = 2.0;

    double scale = job->zoom;
    double xmin = job->centerX - baseHalfWidth * scale;
    double xmax = job->centerX + baseHalfWidth * scale;
    double ymin = job->centerY - baseHalfHeight * scale;
    double ymax = job->centerY + baseHalfHeight * scale;

    for (int y = job->y_start; y < job->y_end; y++) {
        for (int x = 0; x < job->width; x++) {
            double cr = xmin + (x / (double)job->width) * (xmax - xmin);
            double ci = ymin + (y / (double)job->height) * (ymax - ymin);
            double zr = 0, zi = 0;
            int iter = 0;
            while (zr * zr + zi * zi < 4 && iter < job->max_iter) {
                double temp = zr * zr - zi * zi + cr;
                zi = 2 * zr * zi + ci;
                zr = temp;
                iter++;
            }

            double t = (double)iter / job->max_iter;
            uint8_t r = (uint8_t)(9 * (1 - t) * t * t * t * 255);
            uint8_t g = (uint8_t)(15 * (1 - t) * (1 - t) * t * t * 255);
            uint8_t b = (uint8_t)(8.5 * (1 - t) * (1 - t) * (1 - t) * t * 255);

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
    MandelbrotJob* jobs = (MandelbrotJob*)malloc(sizeof(MandelbrotJob) * threads);
    THREAD_HANDLE* handles = (THREAD_HANDLE*)malloc(sizeof(THREAD_HANDLE) * threads);

    int slice = height / threads;
    for (int i = 0; i < threads; i++) {
        jobs[i].pixels = pixels;
        jobs[i].width = width;
        jobs[i].height = height;
        jobs[i].centerX = centerX;
        jobs[i].centerY = centerY;
        jobs[i].zoom = zoom;
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
