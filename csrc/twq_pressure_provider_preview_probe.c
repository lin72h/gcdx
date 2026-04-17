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
	printf("{\"kind\":\"pressure-provider-preview-probe\",\"status\":\"error\","
	    "\"data\":{\"label\":\"%s\",\"stage\":\"%s\",\"rc\":%d,"
	    "\"generation\":%" PRIu64 "},\"meta\":{\"component\":\"c\","
	    "\"binary\":\"twq-pressure-provider-preview-probe\"}}\n",
	    label, stage, error, generation);
	fflush(stdout);
}

static void
emit_provider_done(const char *label, uint64_t sample_count, uint32_t interval_ms,
    uint32_t duration_ms)
{
	printf("{\"kind\":\"pressure-provider-preview-probe\",\"status\":\"ok\","
	    "\"data\":{\"label\":\"%s\",\"sample_count\":%" PRIu64 ","
	    "\"interval_ms\":%u,\"duration_ms\":%u},\"meta\":{"
	    "\"component\":\"c\",\"binary\":\"twq-pressure-provider-preview-probe\"}}\n",
	    label, sample_count, interval_ms, duration_ms);
	fflush(stdout);
}

static void
emit_preview_snapshot(const char *label, uint32_t interval_ms,
    uint32_t duration_ms, uint64_t generation,
    const struct twq_pressure_provider_snapshot_v1 *snapshot)
{
	printf("{\"kind\":\"pressure-provider-preview-snapshot\",\"status\":\"ok\","
	    "\"data\":{\"label\":\"%s\",\"generation\":%" PRIu64 ","
	    "\"interval_ms\":%u,\"duration_ms\":%u,\"snapshot\":{"
	    "\"struct_size\":%zu,"
	    "\"version\":%u,"
	    "\"bucket_count\":%u,"
	    "\"monotonic_time_ns\":%" PRIu64 ","
	    "\"reqthreads_count\":%" PRIu64 ","
	    "\"thread_enter_count\":%" PRIu64 ","
	    "\"thread_return_count\":%" PRIu64 ","
	    "\"switch_block_count\":%" PRIu64 ","
	    "\"switch_unblock_count\":%" PRIu64 ","
	    "\"should_narrow_true_count\":%" PRIu64 ","
	    "\"requested_workers_total\":%" PRIu64 ","
	    "\"admitted_workers_total\":%" PRIu64 ","
	    "\"blocked_workers_total\":%" PRIu64 ","
	    "\"unblocked_workers_total\":%" PRIu64 ","
	    "\"total_workers_current\":%" PRIu64 ","
	    "\"idle_workers_current\":%" PRIu64 ","
	    "\"nonidle_workers_current\":%" PRIu64 ","
	    "\"active_workers_current\":%" PRIu64 ","
	    "\"bucket_req_total\":",
	    label, generation, interval_ms, duration_ms, snapshot->struct_size,
	    snapshot->version, snapshot->bucket_count, snapshot->monotonic_time_ns,
	    snapshot->reqthreads_count, snapshot->thread_enter_count,
	    snapshot->thread_return_count, snapshot->switch_block_count,
	    snapshot->switch_unblock_count, snapshot->should_narrow_true_count,
	    snapshot->requested_workers_total, snapshot->admitted_workers_total,
	    snapshot->blocked_workers_total, snapshot->unblocked_workers_total,
	    snapshot->total_workers_current, snapshot->idle_workers_current,
	    snapshot->nonidle_workers_current, snapshot->active_workers_current);
	emit_u64_array(snapshot->bucket_req_total, snapshot->bucket_count);
	printf(",\"bucket_admit_total\":");
	emit_u64_array(snapshot->bucket_admit_total, snapshot->bucket_count);
	printf(",\"bucket_switch_block_total\":");
	emit_u64_array(snapshot->bucket_switch_block_total, snapshot->bucket_count);
	printf(",\"bucket_switch_unblock_total\":");
	emit_u64_array(snapshot->bucket_switch_unblock_total, snapshot->bucket_count);
	printf(",\"bucket_total_current\":");
	emit_u64_array(snapshot->bucket_total_current, snapshot->bucket_count);
	printf(",\"bucket_idle_current\":");
	emit_u64_array(snapshot->bucket_idle_current, snapshot->bucket_count);
	printf(",\"bucket_nonidle_current\":");
	emit_u64_array(snapshot->bucket_nonidle_current, snapshot->bucket_count);
	printf(",\"bucket_active_current\":");
	emit_u64_array(snapshot->bucket_active_current, snapshot->bucket_count);
	printf("}},\"meta\":{\"component\":\"c\","
	    "\"binary\":\"twq-pressure-provider-preview-probe\"}}\n");
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
	struct twq_pressure_provider_snapshot_v1 snapshot;
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

	deadline_ns = twq_pressure_provider_monotonic_time_ns() +
	    (uint64_t)duration_ms * 1000000ULL;
	generation = 0;
	for (;;) {
		error = twq_pressure_provider_read_snapshot_v1(&snapshot);
		if (error != 0) {
			emit_provider_error(label, "sample-snapshot", error,
			    generation + 1);
			return (1);
		}
		generation++;
		emit_preview_snapshot(label, interval_ms, duration_ms, generation,
		    &snapshot);
		if (twq_pressure_provider_monotonic_time_ns() >= deadline_ns)
			break;
		sleep_millis(interval_ms);
	}

	emit_provider_done(label, generation, interval_ms, duration_ms);
	return (0);
}
