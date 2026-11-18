#ifndef LANG_FOCUS_MATH_H
#define LANG_FOCUS_MATH_H

#include <stdbool.h>

/* Clock minutes since local midnight. Equal endpoints denote an empty window. */
int lang_window_minutes(int start, int end);
bool lang_window_contains(int start, int end, int minute);

/* Intersection of two half-open intervals, in seconds. */
double lang_overlap_seconds(double start, double end, double from, double to);

#endif
