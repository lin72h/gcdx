#include "twq_pressure_provider_bundle.h"

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
	printf("{\"kind\":\"pressure-provider-bundle-probe\",\"status\":\"error\","
	    "\"data\":{\"label\":\"%s\",\"stage\":\"%s\",\"rc\":%d,"
	    "\"generation\":%" PRIu64 "},\"meta\":{\"component\":\"c\","
	    "\"binary\":\"twq-pressure-provider-bundle-probe\"}}\n",
	    label, stage, error, generation);
	fflush(stdout);
}

static void
emit_provider_done(const char *label, uint64_t sample_count, uint32_t interval_ms,
    uint32_t duration_ms)
{
	printf("{\"kind\":\"pressure-provider-bundle-probe\",\"status\":\"ok\","
	    "\"data\":{\"label\":\"%s\",\"sample_count\":%" PRIu64 ","
	    "\"interval_ms\":%u,\"duration_ms\":%u},\"meta\":{"
	    "\"component\":\"c\",\"binary\":\"twq-pressure-provider-bundle-probe\"}}\n",
	    label, sample_count, interval_ms, duration_ms);
	fflush(stdout);
}

static void
emit_bundle_summary(const char *label, uint32_t interval_ms, uint32_t duration_ms,
    const struct twq_pressure_provider_bundle_v1 *bundle)
{
	printf("{\"kind\":\"pressure-provider-bundle-summary\",\"status\":\"ok\","
	    "\"data\":{\"label\":\"%s\",\"interval_ms\":%u,\"duration_ms\":%u,"
	    "\"bundle\":{"
	    "\"struct_size\":%zu,"
	    "\"version\":%u,"
	    "\"source_session_struct_size\":%zu,"
	    "\"source_session_version\":%u,"
	    "\"source_view_struct_size\":%zu,"
	    "\"source_view_version\":%u,"
	    "\"source_observer_struct_size\":%zu,"
	    "\"source_observer_version\":%u,"
	    "\"source_tracker_struct_size\":%zu,"
	    "\"source_tracker_version\":%u,"
	    "\"sample_count\":%" PRIu64 ","
	    "\"generation_first\":%" PRIu64 ","
	    "\"generation_last\":%" PRIu64 ","
	    "\"generation_contiguous\":%s,"
	    "\"monotonic_increasing\":%s,"
	    "\"monotonic_time_first_ns\":%" PRIu64 ","
	    "\"monotonic_time_last_ns\":%" PRIu64 ","
	    "\"current_generation\":%" PRIu64 ","
	    "\"current_monotonic_time_ns\":%" PRIu64 ","
	    "\"current_total_workers_current\":%" PRIu64 ","
	    "\"current_idle_workers_current\":%" PRIu64 ","
	    "\"current_nonidle_workers_current\":%" PRIu64 ","
	    "\"current_active_workers_current\":%" PRIu64 ","
	    "\"current_request_backlog_total\":%" PRIu64 ","
	    "\"current_block_backlog_total\":%" PRIu64 ","
	    "\"current_pressure_visible\":%s,"
	    "\"current_quiescent\":%s,"
	    "\"current_narrow_feedback\":%s,"
	    "\"observer_pressure_visible_samples\":%" PRIu64 ","
	    "\"observer_nonidle_samples\":%" PRIu64 ","
	    "\"observer_request_backlog_samples\":%" PRIu64 ","
	    "\"observer_block_backlog_samples\":%" PRIu64 ","
	    "\"observer_narrow_feedback_samples\":%" PRIu64 ","
	    "\"observer_quiescent_samples\":%" PRIu64 ","
	    "\"observer_max_nonidle_workers_current\":%" PRIu64 ","
	    "\"observer_max_request_backlog_total\":%" PRIu64 ","
	    "\"observer_max_block_backlog_total\":%" PRIu64 ","
	    "\"tracker_pressure_visible_rises\":%" PRIu64 ","
	    "\"tracker_pressure_visible_falls\":%" PRIu64 ","
	    "\"tracker_nonidle_rises\":%" PRIu64 ","
	    "\"tracker_nonidle_falls\":%" PRIu64 ","
	    "\"tracker_request_backlog_rises\":%" PRIu64 ","
	    "\"tracker_request_backlog_falls\":%" PRIu64 ","
	    "\"tracker_block_backlog_rises\":%" PRIu64 ","
	    "\"tracker_block_backlog_falls\":%" PRIu64 ","
	    "\"tracker_narrow_feedback_rises\":%" PRIu64 ","
	    "\"tracker_narrow_feedback_falls\":%" PRIu64 ","
	    "\"tracker_quiescent_rises\":%" PRIu64 ","
	    "\"tracker_quiescent_falls\":%" PRIu64
	    "}},\"meta\":{\"component\":\"c\","
	    "\"binary\":\"twq-pressure-provider-bundle-probe\"}}\n",
	    label, interval_ms, duration_ms, bundle->struct_size, bundle->version,
	    bundle->source_session_struct_size, bundle->source_session_version,
	    bundle->source_view_struct_size, bundle->source_view_version,
	    bundle->source_observer_struct_size, bundle->source_observer_version,
	    bundle->source_tracker_struct_size, bundle->source_tracker_version,
	    bundle->sample_count, bundle->generation_first, bundle->generation_last,
	    bundle->generation_contiguous ? "true" : "false",
	    bundle->monotonic_increasing ? "true" : "false",
	    bundle->monotonic_time_first_ns, bundle->monotonic_time_last_ns,
	    bundle->current_view.generation, bundle->current_view.monotonic_time_ns,
	    bundle->current_view.total_workers_current,
	    bundle->current_view.idle_workers_current,
	    bundle->current_view.nonidle_workers_current,
	    bundle->current_view.active_workers_current,
	    bundle->current_view.request_backlog_total,
	    bundle->current_view.block_backlog_total,
	    bundle->current_pressure_visible ? "true" : "false",
	    bundle->current_quiescent ? "true" : "false",
	    bundle->current_narrow_feedback ? "true" : "false",
	    bundle->observer.pressure_visible_samples,
	    bundle->observer.nonidle_samples,
	    bundle->observer.request_backlog_samples,
	    bundle->observer.block_backlog_samples,
	    bundle->observer.narrow_feedback_samples,
	    bundle->observer.quiescent_samples,
	    bundle->observer.max_nonidle_workers_current,
	    bundle->observer.max_request_backlog_total,
	    bundle->observer.max_block_backlog_total,
	    bundle->tracker.pressure_visible_rises,
	    bundle->tracker.pressure_visible_falls,
	    bundle->tracker.nonidle_rises,
	    bundle->tracker.nonidle_falls,
	    bundle->tracker.request_backlog_rises,
	    bundle->tracker.request_backlog_falls,
	    bundle->tracker.block_backlog_rises,
	    bundle->tracker.block_backlog_falls,
	    bundle->tracker.narrow_feedback_rises,
	    bundle->tracker.narrow_feedback_falls,
	    bundle->tracker.quiescent_rises,
	    bundle->tracker.quiescent_falls);
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
	struct twq_pressure_provider_bundle_v1 bundle;
	const char *label;
	uint64_t deadline_ns;
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

	twq_pressure_provider_bundle_init_v1(&bundle);
	error = twq_pressure_provider_bundle_prime_v1(&bundle);
	if (error != 0) {
		emit_provider_error(label, "bundle-prime", error, 0);
		return (1);
	}

	deadline_ns = twq_pressure_provider_monotonic_time_ns() +
	    (uint64_t)duration_ms * 1000000ULL;
	for (;;) {
		error = twq_pressure_provider_bundle_poll_v1(&bundle);
		if (error != 0) {
			emit_provider_error(label, "bundle-poll", error,
			    bundle.session.next_generation);
			return (1);
		}
		if (twq_pressure_provider_monotonic_time_ns() >= deadline_ns)
			break;
		sleep_millis(interval_ms);
	}

	emit_bundle_summary(label, interval_ms, duration_ms, &bundle);
	emit_provider_done(label, bundle.sample_count, interval_ms, duration_ms);
	return (0);
}
