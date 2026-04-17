#include "twq_pressure_provider_adapter.h"
#include "twq_pressure_provider_preview.h"

#include <errno.h>
#include <inttypes.h>
#include <stdbool.h>
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
emit_u64_array(const uint64_t *values, size_t count)
{
	size_t i;

	putchar('[');
	for (i = 0; i < count; i++) {
		if (i != 0)
			putchar(',');
		printf("%" PRIu64, values[i]);
	}
	putchar(']');
}

static void
emit_provider_error(const char *label, const char *stage, int error,
    uint64_t generation)
{
	printf("{\"kind\":\"pressure-provider-probe\",\"status\":\"error\","
	    "\"data\":{\"label\":\"%s\",\"stage\":\"%s\",\"rc\":%d,"
	    "\"generation\":%" PRIu64 "},\"meta\":{\"component\":\"c\","
	    "\"binary\":\"twq-pressure-provider-probe\"}}\n",
	    label, stage, error, generation);
	fflush(stdout);
}

static void
emit_provider_done(const char *label, uint64_t sample_count, uint32_t interval_ms,
    uint32_t duration_ms)
{
	printf("{\"kind\":\"pressure-provider-probe\",\"status\":\"ok\","
	    "\"data\":{\"label\":\"%s\",\"sample_count\":%" PRIu64 ","
	    "\"interval_ms\":%u,\"duration_ms\":%u},\"meta\":{"
	    "\"component\":\"c\",\"binary\":\"twq-pressure-provider-probe\"}}\n",
	    label, sample_count, interval_ms, duration_ms);
	fflush(stdout);
}

static int
emit_provider_snapshot(const char *label, uint32_t interval_ms,
    uint32_t duration_ms, uint64_t generation,
    const struct twq_pressure_provider_snapshot_v1 *base,
    const struct twq_pressure_provider_snapshot_v1 *current)
{
	struct twq_pressure_provider_view_v1 view;
	uint64_t requested_workers[TWQ_PRESSURE_PROVIDER_MAX_BUCKETS];
	uint64_t admitted_workers[TWQ_PRESSURE_PROVIDER_MAX_BUCKETS];
	uint64_t blocked_workers[TWQ_PRESSURE_PROVIDER_MAX_BUCKETS];
	uint64_t unblocked_workers[TWQ_PRESSURE_PROVIDER_MAX_BUCKETS];
	size_t i;
	int error;

	error = twq_pressure_provider_adapter_build_v1(&view, generation, base,
	    current);
	if (error != 0)
		return (error);

	for (i = 0; i < current->bucket_count; i++) {
		requested_workers[i] = twq_pressure_provider_delta_or_zero_u64(
		    current->bucket_req_total[i], base->bucket_req_total[i]);
		admitted_workers[i] = twq_pressure_provider_delta_or_zero_u64(
		    current->bucket_admit_total[i], base->bucket_admit_total[i]);
		blocked_workers[i] = twq_pressure_provider_delta_or_zero_u64(
		    current->bucket_switch_block_total[i],
		    base->bucket_switch_block_total[i]);
		unblocked_workers[i] = twq_pressure_provider_delta_or_zero_u64(
		    current->bucket_switch_unblock_total[i],
		    base->bucket_switch_unblock_total[i]);
	}

	printf("{\"kind\":\"pressure-provider-snapshot\",\"status\":\"ok\","
	    "\"data\":{\"label\":\"%s\",\"generation\":%" PRIu64 ","
	    "\"monotonic_time_ns\":%" PRIu64 ",\"interval_ms\":%u,"
	    "\"duration_ms\":%u,\"aggregate\":{"
	    "\"request_events_total\":%" PRIu64 ","
	    "\"worker_entries_total\":%" PRIu64 ","
	    "\"worker_returns_total\":%" PRIu64 ","
	    "\"requested_workers_total\":%" PRIu64 ","
	    "\"admitted_workers_total\":%" PRIu64 ","
	    "\"blocked_events_total\":%" PRIu64 ","
	    "\"unblocked_events_total\":%" PRIu64 ","
	    "\"blocked_workers_total\":%" PRIu64 ","
	    "\"unblocked_workers_total\":%" PRIu64 ","
	    "\"total_workers_current\":%" PRIu64 ","
	    "\"idle_workers_current\":%" PRIu64 ","
	    "\"nonidle_workers_current\":%" PRIu64 ","
	    "\"active_workers_current\":%" PRIu64 ","
	    "\"should_narrow_true_total\":%" PRIu64 ","
	    "\"request_backlog_total\":%" PRIu64 ","
	    "\"block_backlog_total\":%" PRIu64 "},"
	    "\"flags\":{"
	    "\"has_per_bucket_diagnostics\":true,"
	    "\"has_admission_feedback\":true,"
	    "\"has_block_feedback\":true,"
	    "\"has_live_current_counts\":true,"
	    "\"has_narrow_feedback\":true,"
	    "\"pressure_visible\":%s},"
	    "\"diagnostics\":{\"per_bucket\":{"
	    "\"requested_workers\":",
	    label, generation, view.monotonic_time_ns, interval_ms, duration_ms,
	    view.request_events_total, view.worker_entries_total,
	    view.worker_returns_total, view.requested_workers_total,
	    view.admitted_workers_total, view.blocked_events_total,
	    view.unblocked_events_total, view.blocked_workers_total,
	    view.unblocked_workers_total, view.total_workers_current,
	    view.idle_workers_current, view.nonidle_workers_current,
	    view.active_workers_current, view.should_narrow_true_total,
	    view.request_backlog_total, view.block_backlog_total,
	    view.pressure_visible ? "true" : "false");
	emit_u64_array(requested_workers, current->bucket_count);
	printf(",\"admitted_workers\":");
	emit_u64_array(admitted_workers, current->bucket_count);
	printf(",\"blocked_workers\":");
	emit_u64_array(blocked_workers, current->bucket_count);
	printf(",\"unblocked_workers\":");
	emit_u64_array(unblocked_workers, current->bucket_count);
	printf(",\"total_workers_current\":");
	emit_u64_array(current->bucket_total_current, current->bucket_count);
	printf(",\"idle_workers_current\":");
	emit_u64_array(current->bucket_idle_current, current->bucket_count);
	printf(",\"nonidle_workers_current\":");
	emit_u64_array(current->bucket_nonidle_current, current->bucket_count);
	printf(",\"active_workers_current\":");
	emit_u64_array(current->bucket_active_current, current->bucket_count);
	printf("}}},\"meta\":{\"component\":\"c\","
	    "\"binary\":\"twq-pressure-provider-probe\"}}\n");
	fflush(stdout);
	return (0);
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
		error = emit_provider_snapshot(label, interval_ms, duration_ms,
		    generation, &base_snapshot, &current_snapshot);
		if (error != 0) {
			emit_provider_error(label, "adapter-build", error,
			    generation);
			return (1);
		}
		if (twq_pressure_provider_monotonic_time_ns() >= deadline_ns)
			break;
		sleep_millis(interval_ms);
	}

	emit_provider_done(label, generation, interval_ms, duration_ms);
	return (0);
}
