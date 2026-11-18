#include "../Shared/FocusMath.h"
#include <assert.h>
#include <limits.h>
#include <stdio.h>

int main(void) {
    assert(lang_window_minutes(9 * 60, 11 * 60) == 120);
    assert(lang_window_minutes(23 * 60 + 55, 10) == 15);
    assert(lang_window_minutes(0, 0) == 0);
    assert(lang_window_minutes(1440, 1) == 0);
    assert(!lang_window_contains(INT_MIN, 10, 60));
    assert(!lang_window_contains(0, 15, 1440));
    assert(lang_window_contains(23 * 60, 7 * 60, 0));
    assert(!lang_window_contains(23 * 60, 7 * 60, 7 * 60));

    /* Compare wrapped windows against an independent minute-by-minute walk. */
    int windows = 0;
    for (int start = 0; start < 1440; start += 37) {
        for (int length = 0; length < 1440; length += 17) {
            const int end = (start + length) % 1440;
            bool expected[1440] = { false };
            for (int offset = 0; offset < length; ++offset) expected[(start + offset) % 1440] = true;
            assert(lang_window_minutes(start, end) == length);
            for (int t = 0; t < 1440; ++t) assert(lang_window_contains(start, end, t) == expected[t]);
            ++windows;
        }
    }

    assert(lang_overlap_seconds(95, 115, 0, 100) == 5);
    assert(lang_overlap_seconds(95, 115, 100, 200) == 15);
    assert(lang_overlap_seconds(50, 100, 100, 200) == 0);
    assert(lang_overlap_seconds(10, 70, 20, 25.5) == 5.5);
    assert(lang_overlap_seconds(30, 25, 0, 100) == 0);
    assert(lang_overlap_seconds(100, 100, 0, 200) == 0);
    printf("%d daily windows checked across every minute; interval tests passed.\n", windows);
    return 0;
}
