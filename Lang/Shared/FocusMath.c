#include "FocusMath.h"
#include <math.h>

enum { minutes_per_day = 1440 };

static bool valid_minute(int value) {
    return value >= 0 && value < minutes_per_day;
}

int lang_window_minutes(int start, int end) {
    if (!valid_minute(start) || !valid_minute(end)) return 0;
    return (end - start + minutes_per_day) % minutes_per_day;
}

bool lang_window_contains(int start, int end, int minute) {
    if (!valid_minute(minute)) return false;
    const int duration = lang_window_minutes(start, end);
    if (duration == 0) return false;
    const int elapsed = (minute - start + minutes_per_day) % minutes_per_day;
    return elapsed < duration;
}

double lang_overlap_seconds(double start, double end, double from, double to) {
    return fmax(0.0, fmin(end, to) - fmax(start, from));
}
