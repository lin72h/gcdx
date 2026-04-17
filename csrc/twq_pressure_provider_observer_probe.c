#include "twq_pressure_provider_adapter.h"
#include "twq_pressure_provider_observer.h"
#include "twq_pressure_provider_preview.h"

#include <errno.h>
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

static void
sleep_millis(uint32_t interval_ms)
{
	struct timespec ts;

	if (interval_ms == 0)
		return;

	ts.tv_sec = interval_ms / 1000U;
	ts.tv_nsec = (long)(interval_ms % 1000U) * 1000000L;
	while (nanosleep(&ts, &ts) != 0 && errno == EINTR)
		continue;
}

static void
emit_provider_error(const char *label, const char *stage, int error,
    uint64_t generation)
{
	printf("{\"kind\":\"pressure-provider-observer-probe\",\"status\":\"error\","
	    "\"data\":{\"label\":\"%s\",\"stage\":\"%s\",\"rc\":%d,"
	    "\"generation\":%" PRIu64 "},\"meta\":{\"component\":\"c\","
	    "\"binary\":\"twq-pressure-provider-observer-probe\"}}\n",
	    label, stage, error, generation);
	fflush(stdout);
}

static void
emit_provider_done(const char *label, uint64_t sample_count, uint32_t interval_ms,
    uint32_t duration_ms)
{
	printf("{\"kind\":\"pressure-provider-observer-probe\",\"status\":\"ok\","
	    "\"data\":{\"label\":\"%s\",\"sample_count\":%" PRIu64 ","
	    "\"interval_ms\":%u,\"duration_ms\":%u},\"meta\":{"
	    "\"component\":\"c\",\"binary\":\"twq-pressure-provider-observer-probe\"}}\n",
	    label, sample_count, interval_ms, duration_ms);
	fflush(stdout);
}

static void
emit_observer_summary(const char *label, uint32_t interval_ms,
    uint32_t duration_ms, const struct twq_pressure_provider_observer_v1 *observer)
{
	printf("{\"kind\":\"pressure-provider-observer-summary\",\"status\":\"ok\","
	    "\"data\":{\"label\":\"%s\",\"interval_ms\":%u,\"duration_ms\":%u,"
	    "\"observer\":{"
	    "\"struct_size\":%zu,"
	    "\"version\":%u,"
	    "\"source_view_struct_size\":%zu,"
	    "\"source_view_version\":%u,"
	    "\"sample_count\":%" PRIu64 ","
	    "\"generation_first\":%" PRIu64 ","
	    "\"generation_last\":%" PRIu64 ","
	    "\"generation_contiguous\":%s,"
	    "\"monotonic_increasing\":%s,"
	    "\"monotonic_time_first_ns\":%" PRIu64 ","
	    "\"monotonic_time_last_ns\":%" PRIu64 ","
	    "\"pressure_visible_samples\":%" PRIu64 ","
	    "\"nonidle_samples\":%" PRIu64 ","
	    "\"request_backlog_samples\":%" PRIu64 ","
	    "\"block_backlog_samples\":%" PRIu64 ","
	    "\"narrow_feedback_samples\":%" PRIu64 ","
	    "\"quiescent_samples\":%" PRIu64 ","
	    "\"max_nonidle_workers_current\":%" PRIu64 ","
	    "\"max_request_backlog_total\":%" PRIu64 ","
	    "\"max_block_backlog_total\":%" PRIu64 ","
	    "\"final_total_workers_current\":%" PRIu64 ","
	    "\"final_idle_workers_current\":%" PRIu64 ","
	    "\"final_nonidle_workers_current\":%" PRIu64 ","
	    "\"final_active_workers_current\":%" PRIu64 ","
	    "\"final_pressure_visible\":%s,"
	    "\"final_quiescent\":%s"
	    "}},\"meta\":{\"component\":\"c\","
	    "\"binary\":\"twq-pressure-provider-observer-probe\"}}\n",
	    label, interval_ms, duration_ms, observer->struct_size,
	    observer->version, observer->source_view_struct_size,
	    observer->source_view_version, observer->sample_count,
	    observer->generation_first, observer->generation_last,
	    observer->generation_contiguous ? "true" : "false",
	    observer->monotonic_increasing ? "true" : "false",
	    observer->monotonic_time_first_ns, observer->monotonic_time_last_ns,
	    observer->pressure_visible_samples, observer->nonidle_samples,
	    observer->request_backlog_samples, observer->block_backlog_samples,
	    observer->narrow_feedback_samples, observer->quiescent_samples,
	    observer->max_nonidle_workers_current,
	    observer->max_request_backlog_total,
	    observer->max_block_backlog_total,
	    observer->final_total_workers_current,
	    observer->final_idle_workers_current,
	    observer->final_nonidle_workers_current,
	    observer->final_active_workers_current,
	    observer->final_pressure_visible ? "true" : "false",
	    observer->final_quiescent ? "true" : "false");
	fflush(stdout);
}

static uint32_t
parse_u32_arg(const char *value, const char *name)
{
	char *end;
	unsigned long parsed;

	parsed = strtoul(value, &end, 10);
	if (value[0] == '\0' || *end != '\0' || parsed > UINT32_MAX) {
		fprintf(stderr, "invalid %s: %s\n", name, value);
		exit(64);
	}
	return ((uint32_t)parsed);
}

int
main(int argc, char **argv)
{
	struct twq_pressure_provider_snapshot_v1 base_snapshot, current_snapshot;
	struct twq_pressure_provider_observer_v1 observer;
	struct twq_pressure_provider_view_v1 view;
	const char *label;
	uint64_t deadline_ns, generation;
	uint32_t duration_ms, interval_ms;
	int error, i;

	label = NULL;
	interval_ms = 50;
	duration_ms = 2000;

	for (i = 1; i < argc; i++) {
		if (strcmp(argv[i], "--label") == 0) {
			if (i + 1 >= argc) {
				fprintf(stderr, "--label requires a value\n");
				return (64);
			}
			label = argv[++i];
		} else if (strcmp(argv[i], "--interval-ms") == 0) {
			if (i + 1 >= argc) {
				fprintf(stderr, "--interval-ms requires a value\n");
				return (64);
			}
			interval_ms = parse_u32_arg(argv[++i], "interval-ms");
		} else if (strcmp(argv[i], "--duration-ms") == 0) {
			if (i + 1 >= argc) {
				fprintf(stderr, "--duration-ms requires a value\n");
				return (64);
			}
			duration_ms = parse_u32_arg(argv[++i], "duration-ms");
		} else if (strcmp(argv[i], "--help") == 0 ||
		    strcmp(argv[i], "-h") == 0) {
			printf("Usage: %s --label <label> [--interval-ms N] "
			    "[--duration-ms N]\n", argv[0]);
			return (0);
		} else {
			fprintf(stderr, "unknown argument: %s\n", argv[i]);
			return (64);
		}
	}

	if (label == NULL || label[0] == '\0') {
		fprintf(stderr, "--label is required\n");
		return (64);
	}

	error = twq_pressure_provider_read_snapshot_v1(&base_snapshot);
	if (error != 0) {
		emit_provider_error(label, "base-snapshot", error, 0);
		return (1);
	}

	twq_pressure_provider_observer_init_v1(&observer);
	deadline_ns = twq_pressure_provider_monotonic_time_ns() +
	    (uint64_t)duration_ms * 1000000ULL;
	generation = 0;
	for (;;) {
		error = twq_pressure_provider_read_snapshot_v1(&current_snapshot);
		if (error != 0) {
			emit_provider_error(label, "sample-snapshot", error,
			    generation + 1);
			return (1);
		}
		generation++;
		error = twq_pressure_provider_adapter_build_v1(&view, generation,
		    &base_snapshot, &current_snapshot);
		if (error != 0) {
			emit_provider_error(label, "adapter-build", error,
			    generation);
			return (1);
		}
		error = twq_pressure_provider_observer_update_v1(&observer, &view);
		if (error != 0) {
			emit_provider_error(label, "observer-update", error,
			    generation);
			return (1);
		}
		if (twq_pressure_provider_monotonic_time_ns() >= deadline_ns)
			break;
		sleep_millis(interval_ms);
	}

	emit_observer_summary(label, interval_ms, duration_ms, &observer);
	emit_provider_done(label, observer.sample_count, interval_ms, duration_ms);
	return (0);
}
