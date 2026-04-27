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
	printf("{\"kind\":\"pressure-provider-session-probe\",\"status\":\"error\","
	    "\"data\":{\"label\":\"%s\",\"stage\":\"%s\",\"rc\":%d,"
	    "\"generation\":%" PRIu64 "},\"meta\":{\"component\":\"c\","
	    "\"binary\":\"twq-pressure-provider-session-probe\"}}\n",
	    label, stage, error, generation);
	fflush(stdout);
}

static void
emit_provider_done(const char *label, uint64_t sample_count, uint32_t interval_ms,
    uint32_t duration_ms)
{
	printf("{\"kind\":\"pressure-provider-session-probe\",\"status\":\"ok\","
	    "\"data\":{\"label\":\"%s\",\"sample_count\":%" PRIu64 ","
	    "\"interval_ms\":%u,\"duration_ms\":%u},\"meta\":{"
	    "\"component\":\"c\",\"binary\":\"twq-pressure-provider-session-probe\"}}\n",
	    label, sample_count, interval_ms, duration_ms);
	fflush(stdout);
}

static void
emit_session_snapshot(const char *label, uint32_t interval_ms,
    uint32_t duration_ms, const struct twq_pressure_provider_session_v1 *session,
    const struct twq_pressure_provider_view_v1 *view)
{
	printf("{\"kind\":\"pressure-provider-session-snapshot\",\"status\":\"ok\","
	    "\"data\":{\"label\":\"%s\",\"generation\":%" PRIu64 ","
	    "\"monotonic_time_ns\":%" PRIu64 ",\"interval_ms\":%u,"
	    "\"duration_ms\":%u,\"session\":{"
	    "\"struct_size\":%zu,"
	    "\"version\":%u,"
	    "\"source_snapshot_struct_size\":%zu,"
	    "\"source_snapshot_version\":%u,"
	    "\"bucket_count\":%u,"
	    "\"next_generation\":%" PRIu64 ","
	    "\"primed\":%s},"
	    "\"view\":{"
	    "\"struct_size\":%zu,"
	    "\"version\":%u,"
	    "\"generation\":%" PRIu64 ","
	    "\"monotonic_time_ns\":%" PRIu64 ","
	    "\"aggregate\":{"
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
	    "\"has_per_bucket_diagnostics\":%s,"
	    "\"has_admission_feedback\":%s,"
	    "\"has_block_feedback\":%s,"
	    "\"has_live_current_counts\":%s,"
	    "\"has_narrow_feedback\":%s,"
	    "\"pressure_visible\":%s}"
	    "}},\"meta\":{\"component\":\"c\","
	    "\"binary\":\"twq-pressure-provider-session-probe\"}}\n",
	    label, view->generation, view->monotonic_time_ns, interval_ms,
	    duration_ms, session->struct_size, session->version,
	    session->source_snapshot_struct_size, session->source_snapshot_version,
	    session->bucket_count, session->next_generation,
	    session->primed ? "true" : "false", view->struct_size, view->version,
	    view->generation, view->monotonic_time_ns,
	    view->request_events_total, view->worker_entries_total,
	    view->worker_returns_total, view->requested_workers_total,
	    view->admitted_workers_total, view->blocked_events_total,
	    view->unblocked_events_total, view->blocked_workers_total,
	    view->unblocked_workers_total, view->total_workers_current,
	    view->idle_workers_current, view->nonidle_workers_current,
	    view->active_workers_current, view->should_narrow_true_total,
	    view->request_backlog_total, view->block_backlog_total,
	    view->has_per_bucket_diagnostics ? "true" : "false",
	    view->has_admission_feedback ? "true" : "false",
	    view->has_block_feedback ? "true" : "false",
	    view->has_live_current_counts ? "true" : "false",
	    view->has_narrow_feedback ? "true" : "false",
	    view->pressure_visible ? "true" : "false");
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
	struct twq_pressure_provider_session_v1 session;
	struct twq_pressure_provider_view_v1 view;
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

	deadline_ns = twq_pressure_provider_monotonic_time_ns() +
	    (uint64_t)duration_ms * 1000000ULL;
	for (;;) {
		error = twq_pressure_provider_session_poll_v1(&session, &view);
		if (error != 0) {
			emit_provider_error(label, "session-poll", error,
			    session.next_generation);
			return (1);
		}
		emit_session_snapshot(label, interval_ms, duration_ms, &session, &view);
		if (twq_pressure_provider_monotonic_time_ns() >= deadline_ns)
			break;
		sleep_millis(interval_ms);
	}

	emit_provider_done(label, view.generation, interval_ms, duration_ms);
	return (0);
}
