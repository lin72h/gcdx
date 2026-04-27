#include "twq_pressure_provider_tracker.h"
#include "twq_pressure_provider_session.h"

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
	printf("{\"kind\":\"pressure-provider-tracker-probe\",\"status\":\"error\","
	    "\"data\":{\"label\":\"%s\",\"stage\":\"%s\",\"rc\":%d,"
	    "\"generation\":%" PRIu64 "},\"meta\":{\"component\":\"c\","
	    "\"binary\":\"twq-pressure-provider-tracker-probe\"}}\n",
	    label, stage, error, generation);
	fflush(stdout);
}

static void
emit_provider_done(const char *label, uint64_t sample_count, uint32_t interval_ms,
    uint32_t duration_ms)
{
	printf("{\"kind\":\"pressure-provider-tracker-probe\",\"status\":\"ok\","
	    "\"data\":{\"label\":\"%s\",\"sample_count\":%" PRIu64 ","
	    "\"interval_ms\":%u,\"duration_ms\":%u},\"meta\":{"
	    "\"component\":\"c\",\"binary\":\"twq-pressure-provider-tracker-probe\"}}\n",
	    label, sample_count, interval_ms, duration_ms);
	fflush(stdout);
}

static void
emit_tracker_summary(const char *label, uint32_t interval_ms,
    uint32_t duration_ms, const struct twq_pressure_provider_tracker_v1 *tracker)
{
	printf("{\"kind\":\"pressure-provider-tracker-summary\",\"status\":\"ok\","
	    "\"data\":{\"label\":\"%s\",\"interval_ms\":%u,\"duration_ms\":%u,"
	    "\"tracker\":{"
	    "\"struct_size\":%zu,"
	    "\"version\":%u,"
	    "\"source_session_struct_size\":%zu,"
	    "\"source_session_version\":%u,"
	    "\"source_view_struct_size\":%zu,"
	    "\"source_view_version\":%u,"
	    "\"sample_count\":%" PRIu64 ","
	    "\"generation_first\":%" PRIu64 ","
	    "\"generation_last\":%" PRIu64 ","
	    "\"generation_contiguous\":%s,"
	    "\"monotonic_increasing\":%s,"
	    "\"monotonic_time_first_ns\":%" PRIu64 ","
	    "\"monotonic_time_last_ns\":%" PRIu64 ","
	    "\"initial_pressure_visible\":%s,"
	    "\"initial_nonidle\":%s,"
	    "\"initial_request_backlog\":%s,"
	    "\"initial_block_backlog\":%s,"
	    "\"initial_narrow_feedback\":%s,"
	    "\"initial_quiescent\":%s,"
	    "\"pressure_visible_rises\":%" PRIu64 ","
	    "\"pressure_visible_falls\":%" PRIu64 ","
	    "\"nonidle_rises\":%" PRIu64 ","
	    "\"nonidle_falls\":%" PRIu64 ","
	    "\"request_backlog_rises\":%" PRIu64 ","
	    "\"request_backlog_falls\":%" PRIu64 ","
	    "\"block_backlog_rises\":%" PRIu64 ","
	    "\"block_backlog_falls\":%" PRIu64 ","
	    "\"narrow_feedback_rises\":%" PRIu64 ","
	    "\"narrow_feedback_falls\":%" PRIu64 ","
	    "\"quiescent_rises\":%" PRIu64 ","
	    "\"quiescent_falls\":%" PRIu64 ","
	    "\"final_pressure_visible\":%s,"
	    "\"final_nonidle\":%s,"
	    "\"final_request_backlog\":%s,"
	    "\"final_block_backlog\":%s,"
	    "\"final_narrow_feedback\":%s,"
	    "\"final_quiescent\":%s"
	    "}},\"meta\":{\"component\":\"c\","
	    "\"binary\":\"twq-pressure-provider-tracker-probe\"}}\n",
	    label, interval_ms, duration_ms, tracker->struct_size,
	    tracker->version, tracker->source_session_struct_size,
	    tracker->source_session_version, tracker->source_view_struct_size,
	    tracker->source_view_version, tracker->sample_count,
	    tracker->generation_first, tracker->generation_last,
	    tracker->generation_contiguous ? "true" : "false",
	    tracker->monotonic_increasing ? "true" : "false",
	    tracker->monotonic_time_first_ns, tracker->monotonic_time_last_ns,
	    tracker->initial_pressure_visible ? "true" : "false",
	    tracker->initial_nonidle ? "true" : "false",
	    tracker->initial_request_backlog ? "true" : "false",
	    tracker->initial_block_backlog ? "true" : "false",
	    tracker->initial_narrow_feedback ? "true" : "false",
	    tracker->initial_quiescent ? "true" : "false",
	    tracker->pressure_visible_rises, tracker->pressure_visible_falls,
	    tracker->nonidle_rises, tracker->nonidle_falls,
	    tracker->request_backlog_rises, tracker->request_backlog_falls,
	    tracker->block_backlog_rises, tracker->block_backlog_falls,
	    tracker->narrow_feedback_rises, tracker->narrow_feedback_falls,
	    tracker->quiescent_rises, tracker->quiescent_falls,
	    tracker->final_pressure_visible ? "true" : "false",
	    tracker->final_nonidle ? "true" : "false",
	    tracker->final_request_backlog ? "true" : "false",
	    tracker->final_block_backlog ? "true" : "false",
	    tracker->final_narrow_feedback ? "true" : "false",
	    tracker->final_quiescent ? "true" : "false");
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
	struct twq_pressure_provider_tracker_v1 tracker;
	struct twq_pressure_provider_session_v1 session;
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

	twq_pressure_provider_session_init_v1(&session);
	error = twq_pressure_provider_session_prime_v1(&session);
	if (error != 0) {
		emit_provider_error(label, "session-prime", error, 0);
		return (1);
	}

	twq_pressure_provider_tracker_init_v1(&tracker);
	deadline_ns = twq_pressure_provider_monotonic_time_ns() +
	    (uint64_t)duration_ms * 1000000ULL;
	for (;;) {
		error = twq_pressure_provider_tracker_poll_session_v1(&tracker,
		    &session);
		if (error != 0) {
			emit_provider_error(label, "tracker-poll-session", error,
			    session.next_generation);
			return (1);
		}
		if (twq_pressure_provider_monotonic_time_ns() >= deadline_ns)
			break;
		sleep_millis(interval_ms);
	}

	emit_tracker_summary(label, interval_ms, duration_ms, &tracker);
	emit_provider_done(label, tracker.sample_count, interval_ms, duration_ms);
	return (0);
}
