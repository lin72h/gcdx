#include <dispatch/dispatch.h>

#include "twq_macos_dispatch_introspection.h"

#include <errno.h>
#include <inttypes.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define DISPATCH_QUEUE_WIDTH_MAX_LOGICAL_CPUS (-3)

extern void dispatch_queue_set_width(dispatch_queue_t dq, long width);

struct dispatch_resume_repeat_probe;

struct dispatch_resume_repeat_child {
	struct dispatch_resume_repeat_probe *probe;
	dispatch_group_t group;
	uint32_t task;
};

struct dispatch_resume_repeat_probe {
	struct dispatch_resume_repeat_child *children;
	dispatch_group_t round_group;
	dispatch_queue_t executor_queue;
	dispatch_queue_t timer_queue;
	const char *mode;
	uint32_t rounds;
	uint32_t tasks;
	uint32_t delay_ms;
	uint32_t current_round;
	uint32_t completed_rounds;
	uint32_t round_sum;
	uint32_t total_sum;
	uint64_t round_start_ns;
	bool dispatch_counters_available;
	struct twq_macos_dispatch_counters round_start_dispatch_counters;
};

static uint64_t
monotonic_now_ns(void)
{
	struct timespec ts;

	if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0)
		return (0);
	return ((uint64_t)ts.tv_sec * 1000000000ULL + (uint64_t)ts.tv_nsec);
}

static void
emit_json(const char *status, const char *fmt, ...)
{
	va_list ap;

	printf("{\"kind\":\"dispatch-probe\",\"status\":\"%s\",\"data\":{", status);
	va_start(ap, fmt);
	vprintf(fmt, ap);
	va_end(ap);
	printf("},\"meta\":{\"component\":\"c\",\"binary\":\"twq-macos-dispatch-resume-repeat\"}}\n");
	fflush(stdout);
}

static dispatch_queue_t
create_executor_queue(void)
{
	dispatch_queue_attr_t attr;
	dispatch_queue_t queue;

	attr = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_CONCURRENT,
	    QOS_CLASS_DEFAULT, 0);
	queue = dispatch_queue_create("twq.macos.executor", attr);
	dispatch_queue_set_width(queue, DISPATCH_QUEUE_WIDTH_MAX_LOGICAL_CPUS);
	return (queue);
}

static void
emit_dispatch_counters(const char *mode, const char *phase, uint32_t round,
		uint32_t completed_rounds,
		const struct twq_macos_dispatch_counters *counters,
		const struct twq_macos_dispatch_counters *start)
{
	emit_json("progress",
	    "\"mode\":\"%s\",\"phase\":\"%s\",\"round\":%u,"
	    "\"completed_rounds\":%u,"
	    "\"root_push_total_default\":%" PRIu64 ","
	    "\"root_push_empty_default\":%" PRIu64 ","
	    "\"root_push_source_default\":%" PRIu64 ","
	    "\"root_push_continuation_default\":%" PRIu64 ","
	    "\"root_poke_slow_default\":%" PRIu64 ","
	    "\"root_requested_threads_default\":%" PRIu64 ","
	    "\"root_push_total_default_overcommit\":%" PRIu64 ","
	    "\"root_push_empty_default_overcommit\":%" PRIu64 ","
	    "\"root_push_mainq_default_overcommit\":%" PRIu64 ","
	    "\"root_push_continuation_default_overcommit\":%" PRIu64 ","
	    "\"root_poke_slow_default_overcommit\":%" PRIu64 ","
	    "\"root_requested_threads_default_overcommit\":%" PRIu64 ","
	    "\"pthread_workqueue_addthreads_calls\":%" PRIu64 ","
	    "\"pthread_workqueue_addthreads_requested_threads\":%" PRIu64,
	    mode, phase, round, completed_rounds,
	    counters->root_push_total_default,
	    counters->root_push_empty_default,
	    counters->root_push_source_default,
	    counters->root_push_continuation_default,
	    counters->root_poke_slow_default,
	    counters->root_requested_threads_default,
	    counters->root_push_total_default_overcommit,
	    counters->root_push_empty_default_overcommit,
	    counters->root_push_mainq_default_overcommit,
	    counters->root_push_continuation_default_overcommit,
	    counters->root_poke_slow_default_overcommit,
	    counters->root_requested_threads_default_overcommit,
	    counters->pthread_workqueue_addthreads_calls,
	    counters->pthread_workqueue_addthreads_requested_threads);

	if (start == NULL)
		return;

	emit_json("progress",
	    "\"mode\":\"%s\",\"phase\":\"%s-delta\",\"round\":%u,"
	    "\"completed_rounds\":%u,"
	    "\"root_push_total_default\":%" PRIu64 ","
	    "\"root_push_empty_default\":%" PRIu64 ","
	    "\"root_push_source_default\":%" PRIu64 ","
	    "\"root_push_continuation_default\":%" PRIu64 ","
	    "\"root_poke_slow_default\":%" PRIu64 ","
	    "\"root_requested_threads_default\":%" PRIu64 ","
	    "\"root_push_total_default_overcommit\":%" PRIu64 ","
	    "\"root_push_empty_default_overcommit\":%" PRIu64 ","
	    "\"root_push_mainq_default_overcommit\":%" PRIu64 ","
	    "\"root_push_continuation_default_overcommit\":%" PRIu64 ","
	    "\"root_poke_slow_default_overcommit\":%" PRIu64 ","
	    "\"root_requested_threads_default_overcommit\":%" PRIu64 ","
	    "\"pthread_workqueue_addthreads_calls\":%" PRIu64 ","
	    "\"pthread_workqueue_addthreads_requested_threads\":%" PRIu64,
	    mode, phase, round, completed_rounds,
	    counters->root_push_total_default - start->root_push_total_default,
	    counters->root_push_empty_default - start->root_push_empty_default,
	    counters->root_push_source_default - start->root_push_source_default,
	    counters->root_push_continuation_default -
	        start->root_push_continuation_default,
	    counters->root_poke_slow_default - start->root_poke_slow_default,
	    counters->root_requested_threads_default -
	        start->root_requested_threads_default,
	    counters->root_push_total_default_overcommit -
	        start->root_push_total_default_overcommit,
	    counters->root_push_empty_default_overcommit -
	        start->root_push_empty_default_overcommit,
	    counters->root_push_mainq_default_overcommit -
	        start->root_push_mainq_default_overcommit,
	    counters->root_push_continuation_default_overcommit -
	        start->root_push_continuation_default_overcommit,
	    counters->root_poke_slow_default_overcommit -
	        start->root_poke_slow_default_overcommit,
	    counters->root_requested_threads_default_overcommit -
	        start->root_requested_threads_default_overcommit,
	    counters->pthread_workqueue_addthreads_calls -
	        start->pthread_workqueue_addthreads_calls,
	    counters->pthread_workqueue_addthreads_requested_threads -
	        start->pthread_workqueue_addthreads_requested_threads);
}

static void
resume_repeat_finish_ok(struct dispatch_resume_repeat_probe *probe)
{
	uint32_t round_sum;

	round_sum = probe->tasks * (probe->tasks - 1) / 2;
	emit_json("ok",
	    "\"mode\":\"%s\",\"phase\":\"after-await\",\"rounds\":%u,"
	    "\"tasks\":%u,\"delay_ms\":%u,\"completed_rounds\":%u,"
	    "\"total_sum\":%u,\"expected_total_sum\":%u",
	    probe->mode, probe->rounds, probe->tasks, probe->delay_ms,
	    probe->completed_rounds, probe->total_sum,
	    probe->rounds * round_sum);
	exit(0);
}

static void
resume_repeat_round_complete_worker(void *ctx);

static void
resume_repeat_resume_worker(void *ctx)
{
	struct dispatch_resume_repeat_child *child;

	child = ctx;
	__atomic_add_fetch(&child->probe->round_sum, child->task, __ATOMIC_SEQ_CST);
	dispatch_group_leave(child->group);
}

static void
resume_repeat_timer_worker(void *ctx)
{
	struct dispatch_resume_repeat_child *child;

	child = ctx;
	dispatch_async_f(child->probe->executor_queue, child,
	    resume_repeat_resume_worker);
}

static void
resume_repeat_start_round(struct dispatch_resume_repeat_probe *probe)
{
	dispatch_group_t group;
	dispatch_time_t when;
	uint32_t i;
	struct twq_macos_dispatch_counters counters;

	probe->round_start_ns = monotonic_now_ns();
	probe->round_sum = 0;
	emit_json("progress",
	    "\"mode\":\"%s\",\"phase\":\"round-start\",\"round\":%u,"
	    "\"completed_rounds\":%u,\"ts_ns\":%" PRIu64,
	    probe->mode, probe->current_round, probe->completed_rounds,
	    probe->round_start_ns);
	if (probe->dispatch_counters_available &&
	    twq_macos_dispatch_introspection_snapshot(&counters) == 0) {
		probe->round_start_dispatch_counters = counters;
		emit_dispatch_counters(probe->mode, "round-start-counters",
		    probe->current_round, probe->completed_rounds, &counters, NULL);
	}

	group = dispatch_group_create();
	probe->round_group = group;
	when = dispatch_time(DISPATCH_TIME_NOW,
	    (int64_t)probe->delay_ms * 1000000LL);
	for (i = 0; i < probe->tasks; i++) {
		probe->children[i].probe = probe;
		probe->children[i].group = group;
		probe->children[i].task = i;
		dispatch_group_enter(group);
		dispatch_after_f(when, probe->timer_queue, &probe->children[i],
		    resume_repeat_timer_worker);
	}

	dispatch_group_notify_f(group, probe->executor_queue, probe,
	    resume_repeat_round_complete_worker);
}

static void
resume_repeat_round_complete_worker(void *ctx)
{
	struct dispatch_resume_repeat_probe *probe;
	struct twq_macos_dispatch_counters counters;
	uint32_t expected_round_sum;
	uint64_t round_end_ns, elapsed_ns;

	probe = ctx;
	expected_round_sum = probe->tasks * (probe->tasks - 1) / 2;
	round_end_ns = monotonic_now_ns();
	elapsed_ns = round_end_ns - probe->round_start_ns;
	probe->completed_rounds++;
	probe->total_sum += probe->round_sum;
	emit_json("progress",
	    "\"mode\":\"%s\",\"phase\":\"round-ok\",\"round\":%u,"
	    "\"round_sum\":%u,\"expected_round_sum\":%u,"
	    "\"completed_rounds\":%u,\"total_sum\":%u,"
	    "\"elapsed_ns\":%" PRIu64 ",\"ts_ns\":%" PRIu64,
	    probe->mode, probe->current_round, probe->round_sum,
	    expected_round_sum, probe->completed_rounds, probe->total_sum,
	    elapsed_ns, round_end_ns);
	if (probe->dispatch_counters_available &&
	    twq_macos_dispatch_introspection_snapshot(&counters) == 0) {
		emit_dispatch_counters(probe->mode, "round-ok-counters",
		    probe->current_round, probe->completed_rounds, &counters,
		    &probe->round_start_dispatch_counters);
	}

	if (probe->round_sum != expected_round_sum) {
		emit_json("error",
		    "\"mode\":\"%s\",\"phase\":\"round-error\",\"round\":%u,"
		    "\"round_sum\":%u,\"expected_round_sum\":%u,"
		    "\"completed_rounds\":%u,\"total_sum\":%u",
		    probe->mode, probe->current_round, probe->round_sum,
		    expected_round_sum, probe->completed_rounds, probe->total_sum);
		exit(1);
	}

	probe->current_round++;
	if (probe->current_round >= probe->rounds)
		resume_repeat_finish_ok(probe);
	resume_repeat_start_round(probe);
}

static void
resume_repeat_root_worker(void *ctx)
{
	struct dispatch_resume_repeat_probe *probe;

	probe = ctx;
	resume_repeat_start_round(probe);
}

static uint32_t
parse_u32_arg(const char *value, const char *name)
{
	char *end;
	unsigned long parsed;

	errno = 0;
	parsed = strtoul(value, &end, 10);
	if (errno != 0 || end == value || *end != '\0' || parsed > UINT32_MAX) {
		fprintf(stderr, "invalid value for %s: %s\n", name, value);
		exit(64);
	}
	return ((uint32_t)parsed);
}

int
main(int argc, char **argv)
{
	struct dispatch_resume_repeat_probe probe;
	uint32_t expected_total_sum;
	uint32_t rounds, tasks, delay_ms;
	int i;

	rounds = 64;
	tasks = 8;
	delay_ms = 20;

	for (i = 1; i < argc; i++) {
		if (strcmp(argv[i], "--mode") == 0) {
			if (++i >= argc) {
				fprintf(stderr, "missing value for --mode\n");
				return (64);
			}
			if (strcmp(argv[i], "main-executor-resume-repeat") != 0) {
				fprintf(stderr, "unsupported mode: %s\n", argv[i]);
				return (64);
			}
			continue;
		}
		if (strcmp(argv[i], "--rounds") == 0) {
			if (++i >= argc) {
				fprintf(stderr, "missing value for --rounds\n");
				return (64);
			}
			rounds = parse_u32_arg(argv[i], "rounds");
			continue;
		}
		if (strcmp(argv[i], "--tasks") == 0) {
			if (++i >= argc) {
				fprintf(stderr, "missing value for --tasks\n");
				return (64);
			}
			tasks = parse_u32_arg(argv[i], "tasks");
			continue;
		}
		if (strcmp(argv[i], "--sleep-ms") == 0) {
			if (++i >= argc) {
				fprintf(stderr, "missing value for --sleep-ms\n");
				return (64);
			}
			delay_ms = parse_u32_arg(argv[i], "sleep-ms");
			continue;
		}

		fprintf(stderr, "unknown argument: %s\n", argv[i]);
		return (64);
	}

	expected_total_sum = rounds * (tasks * (tasks - 1) / 2);
	if (rounds == 0 || tasks == 0) {
		emit_json("ok",
		    "\"mode\":\"main-executor-resume-repeat\",\"phase\":\"after-await\","
		    "\"rounds\":%u,\"tasks\":%u,\"delay_ms\":%u,"
		    "\"completed_rounds\":%u,\"total_sum\":%u,"
		    "\"expected_total_sum\":%u",
		    rounds, tasks, delay_ms, rounds, expected_total_sum,
		    expected_total_sum);
		return (0);
	}

	memset(&probe, 0, sizeof(probe));
	probe.mode = "main-executor-resume-repeat";
	probe.rounds = rounds;
	probe.tasks = tasks;
	probe.delay_ms = delay_ms;
	probe.dispatch_counters_available =
	    twq_macos_dispatch_introspection_install() == 0 &&
	    twq_macos_dispatch_introspection_available() != 0;
	probe.timer_queue = dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0);
	probe.executor_queue = create_executor_queue();
	probe.children = calloc(tasks, sizeof(*probe.children));
	if (probe.children == NULL) {
		perror("calloc");
		return (1);
	}

	if (probe.dispatch_counters_available) {
		emit_json("progress",
		    "\"mode\":\"%s\",\"phase\":\"before-spawn\",\"rounds\":%u,"
		    "\"tasks\":%u,\"delay_ms\":%u,"
		    "\"dispatch_introspection_available\":true",
		    probe.mode, probe.rounds, probe.tasks, probe.delay_ms);
	} else {
		emit_json("progress",
		    "\"mode\":\"%s\",\"phase\":\"before-spawn\",\"rounds\":%u,"
		    "\"tasks\":%u,\"delay_ms\":%u,"
		    "\"dispatch_introspection_available\":false",
		    probe.mode, probe.rounds, probe.tasks, probe.delay_ms);
	}
	if (!probe.dispatch_counters_available) {
		emit_json("progress",
		    "\"mode\":\"%s\",\"phase\":\"dispatch-introspection-error\","
		    "\"message\":\"%s\"",
		    probe.mode,
		    twq_macos_dispatch_introspection_last_error() ?
		    twq_macos_dispatch_introspection_last_error() : "unavailable");
	}
	dispatch_async_f(dispatch_get_main_queue(), &probe,
	    resume_repeat_root_worker);
	dispatch_main();
	return (0);
}
