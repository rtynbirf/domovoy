// fake_time.c — детерминизм genisoimage: фиксируем clock для процесса.
// LD_PRELOAD=... FAKE_EPOCH=1793016000 genisoimage.real ...
#define _GNU_SOURCE
#include <time.h>
#include <sys/time.h>
#include <stdlib.h>
#include <dlfcn.h>

static long fake_epoch(void) {
    static long e = -1;
    if (e < 0) {
        const char *s = getenv("FAKE_EPOCH");
        e = s ? atol(s) : 0;
    }
    return e;
}

time_t time(time_t *t) {
    time_t v = (time_t)fake_epoch();
    if (t) *t = v;
    return v;
}

int gettimeofday(struct timeval *tv, void *tz) {
    if (tv) { tv->tv_sec = fake_epoch(); tv->tv_usec = 0; }
    return 0;
}

int clock_gettime(clockid_t clk, struct timespec *tp) {
    if (tp) { tp->tv_sec = fake_epoch(); tp->tv_nsec = 0; }
    return 0;
}

pid_t getpid(void) { return 1000; }
pid_t getppid(void) { return 999; }

long random(void) { return 424242L; }
int rand(void) { return 4242; }
