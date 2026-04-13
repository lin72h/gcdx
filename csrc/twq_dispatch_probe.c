#include <dispatch/dispatch.h>
#include <pthread/qos.h>
#include <pthread/workqueue_private.h>

#include <sys/param.h>
#include <sys/sysctl.h>
#include <errno.h>
#include <inttypes.h>
#include <pthread.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#define	DISPATCH_PROBE_MAX_THREADS	256
#define	DISPATCH_PROBE_MAX_ROUNDS	16
#define	DISPATCH_PROBE_MAX_SAMPLES	64

#define	DISPATCH_QUEUE_WIDTH_MAX_LOGICAL_CPUS	(-3)

extern void dispatch_queue_set_width(dispatch_queue_t dq, long width);

enum dispatch_probe_mode {
	DISPATCH_PROBE_MODE_BASIC,
	DISPATCH_PROBE_MODE_EXECUTOR,
	DISPATCH_PROBE_MODE_AFTER,
	DISPATCH_PROBE_MODE_EXECUTOR_AFTER,
	DISPATCH_PROBE_MODE_EXECUTOR_AFTER_DEFAULT_WIDTH,
	DISPATCH_PROBE_MODE_EXECUTOR_AFTER_SYNC_WIDTH,
	DISPATCH_PROBE_MODE_EXECUTOR_AFTER_SETTLED,
	DISPATCH_PROBE_MODE_MAIN_EXECUTOR_AFTER_REPEAT,
	DISPATCH_PROBE_MODE_MAIN_EXECUTOR_RESUME_REPEAT,
	DISPATCH_PROBE_MODE_WORKER_AFTER_GROUP,
	DISPATCH_PROBE_MODE_MAIN,
	DISPATCH_PROBE_MODE_MAIN_AFTER,
	DISPATCH_PROBE_MODE_MAIN_ROUNDTRIP_AFTER,
	DISPATCH_PROBE_MODE_MAIN_GROUP_AFTER,
	DISPATCH_PROBE_MODE_PRESSURE,
	DISPATCH_PROBE_MODE_BURST_REUSE,
	DISPATCH_PROBE_MODE_TIMEOUT_GAP,
	DISPATCH_PROBE_MODE_SUSTAINED,
};

enum dispatch_executor_queue_width_mode {
	DISPATCH_EXECUTOR_QUEUE_WIDTH_ASYNC_LOGICAL,
	DISPATCH_EXECUTOR_QUEUE_WIDTH_DEFAULT,
	DISPATCH_EXECUTOR_QUEUE_WIDTH_SYNC_LOGICAL,
};

struct dispatch_probe_state {
	pthread_mutex_t	lock;
	dispatch_group_t	group;
	uintptr_t	main_thread;
	uintptr_t	threads[DISPATCH_PROBE_MAX_THREADS];
	uint32_t	thread_count;
	uint32_t	sleep_ms;
	uint32_t	high_sleep_ms;
	volatile uint32_t started;
	volatile uint32_t completed;
	volatile uint32_t inflight;
	volatile uint32_t max_inflight;
	volatile uint32_t main_thread_callbacks;
	volatile uint32_t high_started;
	volatile uint32_t high_completed;
	volatile uint32_t default_started;
	volatile uint32_t default_completed;
	volatile uint32_t default_inflight;
	volatile uint32_t default_max_inflight;
};

struct dispatch_sampler {
	volatile uint32_t	stop;
	uint32_t		interval_ms;
	uint32_t		sample_count;
	uint32_t		samples_total[DISPATCH_PROBE_MAX_SAMPLES];
	uint32_t		samples_idle[DISPATCH_PROBE_MAX_SAMPLES];
	uint32_t		samples_active[DISPATCH_PROBE_MAX_SAMPLES];
	uint32_t		peak_total;
	uint32_t		peak_idle;
	uint32_t		peak_active;
	int			sysctl_error;
};

struct dispatch_main_probe {
	struct dispatch_probe_state	*state;
	const char			*mode;
	uint32_t			requested;
	uint32_t			delay_ms;
	int				features;
	bool				timed;
};

struct dispatch_main_roundtrip_probe;

struct dispatch_main_roundtrip_item {
	struct dispatch_main_roundtrip_probe *probe;
};

struct dispatch_main_roundtrip_probe {
	struct dispatch_probe_state		*state;
	struct dispatch_main_roundtrip_item	*items;
	const char				*mode;
	uint32_t				requested;
	uint32_t				delay_ms;
	int					features;
};

struct dispatch_main_group_probe;

struct dispatch_main_group_item {
	struct dispatch_main_group_probe *probe;
};

struct dispatch_main_group_probe {
	struct dispatch_probe_state		*state;
	struct dispatch_group_s			*group;
	struct dispatch_main_group_item		*items;
	const char				*mode;
	uint32_t				requested;
	uint32_t				delay_ms;
	int					features;
};

struct dispatch_after_group_probe {
	struct dispatch_probe_state	*state;
	const char			*mode;
	dispatch_semaphore_t		done;
	uint32_t			requested;
	uint32_t			delay_ms;
	uint32_t			timeout_ms;
	int				features;
	volatile int			rc;
};

struct dispatch_repeat_probe;

struct dispatch_twq_round_counters {
	uint32_t	reqthreads_count;
	uint32_t	thread_enter_count;
	uint32_t	thread_return_count;
	uint32_t	bucket_total;
	uint32_t	bucket_idle;
	uint32_t	bucket_active;
};

struct dispatch_repeat_child {
	struct dispatch_repeat_probe	*probe;
	uint32_t			 task;
	volatile uint32_t		 done;
};

struct dispatch_repeat_probe {
	struct dispatch_probe_state	*state;
	struct dispatch_repeat_child	*children;
	dispatch_queue_t		 executor_queue;
	dispatch_queue_t		 timer_queue;
	const char			*mode;
	uint32_t			 rounds;
	uint32_t			 tasks;
	uint32_t			 delay_ms;
	uint32_t			 current_round;
	uint32_t			 current_task;
	uint32_t			 round_sum;
	uint32_t			 completed_rounds;
	uint32_t			 total_sum;
	volatile uint32_t		 parent_scheduled;
	struct dispatch_twq_round_counters round_start_counters;
	int				 round_start_sysctl_error;
	int				 features;
};

struct dispatch_resume_repeat_probe;

struct dispatch_resume_repeat_child {
	struct dispatch_resume_repeat_probe *probe;
	dispatch_group_t			  group;
	uint32_t				  task;
	uint32_t				  round;
};

struct dispatch_resume_repeat_probe {
	struct dispatch_probe_state		*state;
	struct dispatch_resume_repeat_child	*children;
	dispatch_queue_t			 executor_queue;
	dispatch_queue_t			 timer_queue;
	dispatch_group_t			 round_group;
	const char				*mode;
	uint32_t				 rounds;
	uint32_t				 tasks;
	uint32_t				 delay_ms;
	uint32_t				 current_round;
	uint32_t				 round_sum;
	uint32_t				 completed_rounds;
	uint32_t				 total_sum;
	struct dispatch_twq_round_counters	 round_start_counters;
	int					 round_start_sysctl_error;
	int					 features;
};

static uint32_t
dispatch_warm_floor(void)
{
	long cpus;

	cpus = sysconf(_SC_NPROCESSORS_ONLN);
	if (cpus < 1)
		return (1);
	if (cpus > 4)
		cpus = 4;
	return ((uint32_t)cpus);
}

static void
emit_u32_json_array(const uint32_t *values, uint32_t count)
{
	uint32_t i;

	putchar('[');
	for (i = 0; i < count; i++) {
		if (i != 0)
			putchar(',');
		printf("%u", values[i]);
	}
	putchar(']');
}

static void
emit_basic_result(const char *mode, const char *status, int rc,
    uint32_t requested,
    uint32_t started, uint32_t completed, uint32_t unique_threads,
    uint32_t max_inflight, uint32_t main_thread_callbacks, bool timed_out,
    int features)
{

	printf("{\"kind\":\"dispatch-probe\",\"status\":\"%s\",\"data\":{"
	    "\"mode\":\"%s\",\"rc\":%d,\"requested\":%u,\"started\":%u,"
	    "\"completed\":%u,\"unique_threads\":%u,\"max_inflight\":%u,"
	    "\"main_thread_callbacks\":%u,\"timed_out\":%s,\"features\":%d},"
	    "\"meta\":{\"component\":\"c\",\"binary\":\"twq-dispatch-probe\"}}\n",
	    status, mode, rc, requested, started, completed, unique_threads,
	    max_inflight, main_thread_callbacks, timed_out ? "true" : "false",
	    features);
	fflush(stdout);
}

static void
emit_after_result(const char *mode, const char *status, int rc,
    uint32_t requested,
    uint32_t delay_ms, uint32_t started, uint32_t completed,
    uint32_t unique_threads, uint32_t max_inflight,
    uint32_t main_thread_callbacks, bool timed_out, int features)
{

	printf("{\"kind\":\"dispatch-probe\",\"status\":\"%s\",\"data\":{"
	    "\"mode\":\"%s\",\"rc\":%d,\"requested\":%u,"
	    "\"delay_ms\":%u,\"started\":%u,\"completed\":%u,"
	    "\"unique_threads\":%u,\"max_inflight\":%u,"
	    "\"main_thread_callbacks\":%u,\"timed_out\":%s,\"features\":%d},"
	    "\"meta\":{\"component\":\"c\",\"binary\":\"twq-dispatch-probe\"}}\n",
	    status, mode, rc, requested, delay_ms, started, completed,
	    unique_threads,
	    max_inflight, main_thread_callbacks, timed_out ? "true" : "false",
	    features);
	fflush(stdout);
}

static void
emit_repeat_result(const char *mode, const char *status, int rc,
    uint32_t rounds, uint32_t tasks, uint32_t delay_ms,
    uint32_t completed_rounds, uint32_t total_sum, uint32_t expected_total_sum,
    uint32_t started, uint32_t completed, uint32_t unique_threads,
    uint32_t max_inflight, uint32_t main_thread_callbacks, bool timed_out,
    int features)
{

	printf("{\"kind\":\"dispatch-probe\",\"status\":\"%s\",\"data\":{"
	    "\"mode\":\"%s\",\"rc\":%d,\"rounds\":%u,\"tasks\":%u,"
	    "\"delay_ms\":%u,\"completed_rounds\":%u,\"total_sum\":%u,"
	    "\"expected_total_sum\":%u,\"started\":%u,\"completed\":%u,"
	    "\"unique_threads\":%u,\"max_inflight\":%u,"
	    "\"main_thread_callbacks\":%u,\"timed_out\":%s,\"features\":%d},"
	    "\"meta\":{\"component\":\"c\",\"binary\":\"twq-dispatch-probe\"}}\n",
	    status, mode, rc, rounds, tasks, delay_ms, completed_rounds,
	    total_sum, expected_total_sum, started, completed, unique_threads,
	    max_inflight, main_thread_callbacks, timed_out ? "true" : "false",
	    features);
	fflush(stdout);
}

static void
emit_pressure_result(const char *status, int rc, uint32_t requested_default,
    uint32_t requested_high, uint32_t started_default,
    uint32_t completed_default, uint32_t started_high,
    uint32_t completed_high, uint32_t unique_threads,
    uint32_t default_max_inflight, uint32_t main_thread_callbacks,
    bool timed_out, int features)
{

	printf("{\"kind\":\"dispatch-probe\",\"status\":\"%s\",\"data\":{"
	    "\"mode\":\"pressure\",\"rc\":%d,\"requested_default\":%u,"
	    "\"requested_high\":%u,\"started_default\":%u,"
	    "\"completed_default\":%u,\"started_high\":%u,"
	    "\"completed_high\":%u,\"unique_threads\":%u,"
	    "\"default_max_inflight\":%u,\"main_thread_callbacks\":%u,"
	    "\"timed_out\":%s,\"features\":%d},"
	    "\"meta\":{\"component\":\"c\",\"binary\":\"twq-dispatch-probe\"}}\n",
	    status, rc, requested_default, requested_high, started_default,
	    completed_default, started_high, completed_high, unique_threads,
	    default_max_inflight, main_thread_callbacks,
	    timed_out ? "true" : "false", features);
	fflush(stdout);
}

static void
emit_burst_result(const char *mode, const char *status, int rc, uint32_t rounds,
    uint32_t requested, uint32_t started, uint32_t completed,
    uint32_t unique_threads, uint32_t max_inflight,
    uint32_t main_thread_callbacks, uint32_t rounds_completed,
    const uint32_t *round_unique_threads, const uint32_t *round_new_threads,
    const uint32_t *round_rest_total, const uint32_t *round_rest_idle,
    const uint32_t *round_rest_active, const uint32_t *round_thread_enter_delta,
    const uint32_t *round_reqthreads_delta,
    const uint32_t *round_should_narrow_true_delta, uint32_t settled_total,
    uint32_t settled_idle, uint32_t settled_active, uint32_t warm_floor,
    int sysctl_error, bool timed_out, int features)
{

	printf("{\"kind\":\"dispatch-probe\",\"status\":\"%s\",\"data\":{"
	    "\"mode\":\"%s\",\"rc\":%d,\"rounds\":%u,"
	    "\"rounds_completed\":%u,\"requested\":%u,\"started\":%u,"
	    "\"completed\":%u,\"unique_threads\":%u,\"max_inflight\":%u,"
	    "\"main_thread_callbacks\":%u,\"round_unique_threads\":",
	    status, mode, rc, rounds, rounds_completed, requested, started,
	    completed, unique_threads, max_inflight, main_thread_callbacks);
	emit_u32_json_array(round_unique_threads, rounds_completed);
	printf(",\"round_new_threads\":");
	emit_u32_json_array(round_new_threads, rounds_completed);
	printf(",\"round_rest_total\":");
	emit_u32_json_array(round_rest_total, rounds_completed);
	printf(",\"round_rest_idle\":");
	emit_u32_json_array(round_rest_idle, rounds_completed);
	printf(",\"round_rest_active\":");
	emit_u32_json_array(round_rest_active, rounds_completed);
	printf(",\"round_thread_enter_delta\":");
	emit_u32_json_array(round_thread_enter_delta, rounds_completed);
	printf(",\"round_reqthreads_delta\":");
	emit_u32_json_array(round_reqthreads_delta, rounds_completed);
	printf(",\"round_should_narrow_true_delta\":");
	emit_u32_json_array(round_should_narrow_true_delta, rounds_completed);
	printf(",\"settled_total\":%u,\"settled_idle\":%u,"
	    "\"settled_active\":%u,\"warm_floor\":%u,\"sysctl_error\":%d,"
	    "\"timed_out\":%s,\"features\":%d},"
	    "\"meta\":{\"component\":\"c\","
	    "\"binary\":\"twq-dispatch-probe\"}}\n",
	    settled_total, settled_idle, settled_active, warm_floor,
	    sysctl_error, timed_out ? "true" : "false", features);
	fflush(stdout);
}

static void
emit_sustained_result(const char *status, int rc, uint32_t requested_default,
    uint32_t requested_high, uint32_t started_default,
    uint32_t completed_default, uint32_t started_high,
    uint32_t completed_high, uint32_t unique_threads,
    uint32_t default_max_inflight, uint32_t peak_sample_total,
    uint32_t peak_sample_idle, uint32_t peak_sample_active,
    uint32_t sample_count, const uint32_t *samples_total,
    const uint32_t *samples_idle, const uint32_t *samples_active,
    uint32_t settled_total, uint32_t settled_idle, uint32_t settled_active,
    uint32_t main_thread_callbacks, uint32_t warm_floor, bool high_ready,
    int sysctl_error, bool timed_out, int features)
{

	printf("{\"kind\":\"dispatch-probe\",\"status\":\"%s\",\"data\":{"
	    "\"mode\":\"sustained\",\"rc\":%d,\"requested_default\":%u,"
	    "\"requested_high\":%u,\"started_default\":%u,"
	    "\"completed_default\":%u,\"started_high\":%u,"
	    "\"completed_high\":%u,\"unique_threads\":%u,"
	    "\"default_max_inflight\":%u,\"peak_sample_total\":%u,"
	    "\"peak_sample_idle\":%u,\"peak_sample_active\":%u,"
	    "\"sample_count\":%u,\"samples_total\":",
	    status, rc, requested_default, requested_high, started_default,
	    completed_default, started_high, completed_high, unique_threads,
	    default_max_inflight, peak_sample_total, peak_sample_idle,
	    peak_sample_active, sample_count);
	emit_u32_json_array(samples_total, sample_count);
	printf(",\"samples_idle\":");
	emit_u32_json_array(samples_idle, sample_count);
	printf(",\"samples_active\":");
	emit_u32_json_array(samples_active, sample_count);
	printf(",\"settled_total\":%u,\"settled_idle\":%u,"
	    "\"settled_active\":%u,\"main_thread_callbacks\":%u,"
	    "\"warm_floor\":%u,\"high_ready\":%s,\"sysctl_error\":%d,"
	    "\"timed_out\":%s,\"features\":%d},"
	    "\"meta\":{\"component\":\"c\","
	    "\"binary\":\"twq-dispatch-probe\"}}\n",
	    settled_total, settled_idle, settled_active, main_thread_callbacks,
	    warm_floor, high_ready ? "true" : "false", sysctl_error,
	    timed_out ? "true" : "false", features);
	fflush(stdout);
}

static void
emit_supported_result(int features)
{

	printf("{\"kind\":\"dispatch-probe\",\"status\":\"ok\",\"data\":{"
	    "\"mode\":\"supported\",\"rc\":%d,\"features\":%d},"
	    "\"meta\":{\"component\":\"c\",\"binary\":\"twq-dispatch-probe\"}}\n",
	    features, features);
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

static enum dispatch_probe_mode
parse_mode_arg(const char *value)
{

	if (strcmp(value, "basic") == 0)
		return (DISPATCH_PROBE_MODE_BASIC);
	if (strcmp(value, "executor") == 0)
		return (DISPATCH_PROBE_MODE_EXECUTOR);
	if (strcmp(value, "after") == 0)
		return (DISPATCH_PROBE_MODE_AFTER);
	if (strcmp(value, "executor-after") == 0)
		return (DISPATCH_PROBE_MODE_EXECUTOR_AFTER);
	if (strcmp(value, "executor-after-default-width") == 0)
		return (DISPATCH_PROBE_MODE_EXECUTOR_AFTER_DEFAULT_WIDTH);
	if (strcmp(value, "executor-after-sync-width") == 0)
		return (DISPATCH_PROBE_MODE_EXECUTOR_AFTER_SYNC_WIDTH);
	if (strcmp(value, "executor-after-settled") == 0)
		return (DISPATCH_PROBE_MODE_EXECUTOR_AFTER_SETTLED);
	if (strcmp(value, "main-executor-after-repeat") == 0)
		return (DISPATCH_PROBE_MODE_MAIN_EXECUTOR_AFTER_REPEAT);
	if (strcmp(value, "main-executor-resume-repeat") == 0)
		return (DISPATCH_PROBE_MODE_MAIN_EXECUTOR_RESUME_REPEAT);
	if (strcmp(value, "worker-after-group") == 0)
		return (DISPATCH_PROBE_MODE_WORKER_AFTER_GROUP);
	if (strcmp(value, "main") == 0)
		return (DISPATCH_PROBE_MODE_MAIN);
	if (strcmp(value, "main-after") == 0)
		return (DISPATCH_PROBE_MODE_MAIN_AFTER);
	if (strcmp(value, "main-roundtrip-after") == 0)
		return (DISPATCH_PROBE_MODE_MAIN_ROUNDTRIP_AFTER);
	if (strcmp(value, "main-group-after") == 0)
		return (DISPATCH_PROBE_MODE_MAIN_GROUP_AFTER);
	if (strcmp(value, "pressure") == 0)
		return (DISPATCH_PROBE_MODE_PRESSURE);
	if (strcmp(value, "burst-reuse") == 0)
		return (DISPATCH_PROBE_MODE_BURST_REUSE);
	if (strcmp(value, "timeout-gap") == 0)
		return (DISPATCH_PROBE_MODE_TIMEOUT_GAP);
	if (strcmp(value, "sustained") == 0)
		return (DISPATCH_PROBE_MODE_SUSTAINED);
	fprintf(stderr, "invalid mode: %s\n", value);
	exit(64);
}

static void
update_max(volatile uint32_t *target, uint32_t candidate)
{
	uint32_t current;

	current = __atomic_load_n(target, __ATOMIC_SEQ_CST);
	while (candidate > current &&
	    !__atomic_compare_exchange_n(target, &current, candidate, false,
	    __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST)) {
		/* retry */
	}
}

static void
record_thread(struct dispatch_probe_state *state, uintptr_t thread_id)
{
	uint32_t i;

	pthread_mutex_lock(&state->lock);
	for (i = 0; i < state->thread_count; i++) {
		if (state->threads[i] == thread_id) {
			pthread_mutex_unlock(&state->lock);
			return;
		}
	}
	if (state->thread_count < nitems(state->threads))
		state->threads[state->thread_count++] = thread_id;
	pthread_mutex_unlock(&state->lock);
}

static uint32_t
unique_thread_count(struct dispatch_probe_state *state)
{
	uint32_t count;

	pthread_mutex_lock(&state->lock);
	count = state->thread_count;
	pthread_mutex_unlock(&state->lock);
	return (count);
}

static void
record_common(struct dispatch_probe_state *state)
{
	uintptr_t thread_id;

	thread_id = (uintptr_t)pthread_self();
	if (thread_id == state->main_thread)
		__atomic_add_fetch(&state->main_thread_callbacks, 1,
		    __ATOMIC_SEQ_CST);
	record_thread(state, thread_id);
}

static bool
wait_for_counter(const volatile uint32_t *counter, uint32_t target,
    uint32_t timeout_ms)
{
	uint32_t elapsed_ms, value;

	for (elapsed_ms = 0; elapsed_ms < timeout_ms; elapsed_ms++) {
		value = __atomic_load_n(counter, __ATOMIC_SEQ_CST);
		if (value >= target)
			return (true);
		usleep(1000);
	}
	return (__atomic_load_n(counter, __ATOMIC_SEQ_CST) >= target);
}

static int
read_sysctl_text(const char *name, char *buf, size_t buf_size)
{
	size_t len;

	len = buf_size;
	if (sysctlbyname(name, buf, &len, NULL, 0) != 0)
		return (errno);
	if (len == 0) {
		buf[0] = '\0';
		return (0);
	}
	if (len >= buf_size)
		len = buf_size - 1;
	buf[len] = '\0';
	return (0);
}

static int
sum_sysctl_bucket_values(const char *name, uint32_t *sum_out)
{
	char buf[128];
	char *cursor, *end;
	unsigned long value, sum;
	int error;

	error = read_sysctl_text(name, buf, sizeof(buf));
	if (error != 0)
		return (error);

	sum = 0;
	cursor = buf;
	while (*cursor != '\0') {
		value = strtoul(cursor, &end, 10);
		if (end == cursor)
			return (EPROTO);
		if (value > UINT32_MAX || sum + value > UINT32_MAX)
			return (ERANGE);
		sum += value;
		if (*end == '\0')
			break;
		if (*end != ',')
			return (EPROTO);
		cursor = end + 1;
	}

	*sum_out = (uint32_t)sum;
	return (0);
}

static int
read_sysctl_u32_text(const char *name, uint32_t *value_out)
{
	size_t len;
	uint64_t value;
	int error;

	len = sizeof(value);
	value = 0;
	if (sysctlbyname(name, &value, &len, NULL, 0) != 0)
		return (errno);
	if (len != sizeof(uint32_t) && len != sizeof(u_long) &&
	    len != sizeof(uint64_t))
		return (EPROTO);
	if (value > UINT32_MAX)
		return (ERANGE);
	error = 0;
	if (value_out != NULL)
		*value_out = (uint32_t)value;
	return (error);
}

static int
read_bucket_sums(uint32_t *total_out, uint32_t *idle_out, uint32_t *active_out)
{
	int error;

	error = sum_sysctl_bucket_values("kern.twq.bucket_total_current",
	    total_out);
	if (error != 0)
		return (error);
	error = sum_sysctl_bucket_values("kern.twq.bucket_idle_current",
	    idle_out);
	if (error != 0)
		return (error);
	error = sum_sysctl_bucket_values("kern.twq.bucket_active_current",
	    active_out);
	if (error != 0)
		return (error);
	return (0);
}

static int
read_twq_round_counters(struct dispatch_twq_round_counters *counters)
{
	int error;

	memset(counters, 0, sizeof(*counters));
	error = read_sysctl_u32_text("kern.twq.reqthreads_count",
	    &counters->reqthreads_count);
	if (error != 0)
		return (error);
	error = read_sysctl_u32_text("kern.twq.thread_enter_count",
	    &counters->thread_enter_count);
	if (error != 0)
		return (error);
	error = read_sysctl_u32_text("kern.twq.thread_return_count",
	    &counters->thread_return_count);
	if (error != 0)
		return (error);
	error = read_bucket_sums(&counters->bucket_total, &counters->bucket_idle,
	    &counters->bucket_active);
	return (error);
}

static void
sleep_millis(uint32_t sleep_ms)
{
	struct timespec ts;

	if (sleep_ms == 0)
		return;

	ts.tv_sec = sleep_ms / 1000U;
	ts.tv_nsec = (long)(sleep_ms % 1000U) * 1000000L;
	while (nanosleep(&ts, &ts) != 0 && errno == EINTR)
		continue;
}

static void *
dispatch_sampler_main(void *arg)
{
	struct dispatch_sampler *sampler;
	uint32_t active, idle, total;
	uint32_t count;
	int error;

	sampler = arg;
	for (;;) {
		error = read_bucket_sums(&total, &idle, &active);
		if (error != 0) {
			sampler->sysctl_error = error;
			break;
		}
		count = sampler->sample_count;
		if (count < nitems(sampler->samples_total)) {
			sampler->samples_total[count] = total;
			sampler->samples_idle[count] = idle;
			sampler->samples_active[count] = active;
			sampler->sample_count = count + 1;
			if (total > sampler->peak_total)
				sampler->peak_total = total;
			if (idle > sampler->peak_idle)
				sampler->peak_idle = idle;
			if (active > sampler->peak_active)
				sampler->peak_active = active;
		}
		if (__atomic_load_n(&sampler->stop, __ATOMIC_SEQ_CST) != 0 ||
		    sampler->sample_count >= nitems(sampler->samples_total))
			break;
		sleep_millis(sampler->interval_ms);
	}

	return (NULL);
}

static void
basic_worker(void *ctx)
{
	struct dispatch_probe_state *state;
	uint32_t inflight;

	state = ctx;
	__atomic_add_fetch(&state->started, 1, __ATOMIC_SEQ_CST);
	inflight = __atomic_add_fetch(&state->inflight, 1, __ATOMIC_SEQ_CST);
	update_max(&state->max_inflight, inflight);
	record_common(state);
	sleep_millis(state->sleep_ms);
	__atomic_sub_fetch(&state->inflight, 1, __ATOMIC_SEQ_CST);
	__atomic_add_fetch(&state->completed, 1, __ATOMIC_SEQ_CST);
}

static void
basic_leave_worker(void *ctx)
{
	struct dispatch_probe_state *state;

	state = ctx;
	basic_worker(ctx);
	dispatch_group_leave(state->group);
}

static void
after_worker(void *ctx)
{
	struct dispatch_probe_state *state;
	uint32_t inflight;

	state = ctx;
	__atomic_add_fetch(&state->started, 1, __ATOMIC_SEQ_CST);
	inflight = __atomic_add_fetch(&state->inflight, 1, __ATOMIC_SEQ_CST);
	update_max(&state->max_inflight, inflight);
	record_common(state);
	__atomic_sub_fetch(&state->inflight, 1, __ATOMIC_SEQ_CST);
	__atomic_add_fetch(&state->completed, 1, __ATOMIC_SEQ_CST);
	dispatch_group_leave(state->group);
}

static void
main_queue_exit_worker(void *ctx)
{
	struct dispatch_main_probe *probe;
	struct dispatch_probe_state *state;
	uint32_t completed, inflight, main_thread_callbacks, max_inflight, started;
	uint32_t unique_threads;

	probe = ctx;
	state = probe->state;
	__atomic_add_fetch(&state->started, 1, __ATOMIC_SEQ_CST);
	inflight = __atomic_add_fetch(&state->inflight, 1, __ATOMIC_SEQ_CST);
	update_max(&state->max_inflight, inflight);
	record_common(state);
	__atomic_sub_fetch(&state->inflight, 1, __ATOMIC_SEQ_CST);
	completed = __atomic_add_fetch(&state->completed, 1, __ATOMIC_SEQ_CST);
	if (completed != probe->requested)
		return;

	started = __atomic_load_n(&state->started, __ATOMIC_SEQ_CST);
	max_inflight = __atomic_load_n(&state->max_inflight, __ATOMIC_SEQ_CST);
	main_thread_callbacks = __atomic_load_n(&state->main_thread_callbacks,
	    __ATOMIC_SEQ_CST);
	unique_threads = unique_thread_count(state);

	if (probe->timed) {
		emit_after_result(probe->mode, "ok", 0, probe->requested,
		    probe->delay_ms, started, completed, unique_threads,
		    max_inflight, main_thread_callbacks, false, probe->features);
	} else {
		emit_basic_result(probe->mode, "ok", 0, probe->requested,
		    started, completed, unique_threads, max_inflight,
		    main_thread_callbacks, false, probe->features);
	}
	exit(0);
}

static void
main_roundtrip_complete_worker(void *ctx)
{
	struct dispatch_main_roundtrip_item *item;
	struct dispatch_main_roundtrip_probe *probe;
	struct dispatch_probe_state *state;
	uint32_t completed, main_thread_callbacks, max_inflight, started;
	uint32_t unique_threads;

	item = ctx;
	probe = item->probe;
	state = probe->state;
	record_common(state);
	__atomic_sub_fetch(&state->inflight, 1, __ATOMIC_SEQ_CST);
	completed = __atomic_add_fetch(&state->completed, 1, __ATOMIC_SEQ_CST);
	if (completed != probe->requested)
		return;

	started = __atomic_load_n(&state->started, __ATOMIC_SEQ_CST);
	max_inflight = __atomic_load_n(&state->max_inflight, __ATOMIC_SEQ_CST);
	main_thread_callbacks = __atomic_load_n(&state->main_thread_callbacks,
	    __ATOMIC_SEQ_CST);
	unique_threads = unique_thread_count(state);
	emit_after_result(probe->mode, "ok", 0, probe->requested,
	    probe->delay_ms, started, completed, unique_threads, max_inflight,
	    main_thread_callbacks, false, probe->features);
	exit(0);
}

static void
main_roundtrip_after_worker(void *ctx)
{
	struct dispatch_main_roundtrip_item *item;
	struct dispatch_main_roundtrip_probe *probe;
	struct dispatch_probe_state *state;
	uint32_t inflight;

	item = ctx;
	probe = item->probe;
	state = probe->state;
	__atomic_add_fetch(&state->started, 1, __ATOMIC_SEQ_CST);
	inflight = __atomic_add_fetch(&state->inflight, 1, __ATOMIC_SEQ_CST);
	update_max(&state->max_inflight, inflight);
	record_common(state);
	dispatch_async_f(dispatch_get_main_queue(), item,
	    main_roundtrip_complete_worker);
}

static void
main_roundtrip_root_worker(void *ctx)
{
	struct dispatch_main_roundtrip_probe *probe;
	struct dispatch_probe_state *state;
	dispatch_queue_t queue;
	dispatch_time_t when;
	uint32_t i;

	probe = ctx;
	state = probe->state;
	record_common(state);
	queue = dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0);
	when = dispatch_time(DISPATCH_TIME_NOW,
	    (int64_t)probe->delay_ms * 1000000LL);

	for (i = 0; i < probe->requested; i++) {
		dispatch_after_f(when, queue, &probe->items[i],
		    main_roundtrip_after_worker);
	}
}

static void
main_group_notify_worker(void *ctx)
{
	struct dispatch_main_group_probe *probe;
	struct dispatch_probe_state *state;
	uint32_t completed, main_thread_callbacks, max_inflight, started;
	uint32_t unique_threads;

	probe = ctx;
	state = probe->state;
	record_common(state);
	started = __atomic_load_n(&state->started, __ATOMIC_SEQ_CST);
	completed = __atomic_load_n(&state->completed, __ATOMIC_SEQ_CST);
	max_inflight = __atomic_load_n(&state->max_inflight, __ATOMIC_SEQ_CST);
	main_thread_callbacks = __atomic_load_n(&state->main_thread_callbacks,
	    __ATOMIC_SEQ_CST);
	unique_threads = unique_thread_count(state);
	emit_after_result(probe->mode,
	    completed == probe->requested ? "ok" : "error",
	    completed == probe->requested ? 0 : 1,
	    probe->requested, probe->delay_ms, started, completed,
	    unique_threads, max_inflight, main_thread_callbacks, false,
	    probe->features);
	exit(completed == probe->requested ? 0 : 1);
}

static void
main_group_after_worker(void *ctx)
{
	struct dispatch_main_group_item *item;
	struct dispatch_main_group_probe *probe;
	struct dispatch_probe_state *state;
	uint32_t inflight;

	item = ctx;
	probe = item->probe;
	state = probe->state;
	__atomic_add_fetch(&state->started, 1, __ATOMIC_SEQ_CST);
	inflight = __atomic_add_fetch(&state->inflight, 1, __ATOMIC_SEQ_CST);
	update_max(&state->max_inflight, inflight);
	record_common(state);
	__atomic_sub_fetch(&state->inflight, 1, __ATOMIC_SEQ_CST);
	__atomic_add_fetch(&state->completed, 1, __ATOMIC_SEQ_CST);
	dispatch_group_leave(probe->group);
}

static void
main_group_root_worker(void *ctx)
{
	struct dispatch_main_group_probe *probe;
	struct dispatch_probe_state *state;
	dispatch_queue_t queue;
	dispatch_time_t when;
	uint32_t i;

	probe = ctx;
	state = probe->state;
	record_common(state);
	queue = dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0);
	when = dispatch_time(DISPATCH_TIME_NOW,
	    (int64_t)probe->delay_ms * 1000000LL);

	for (i = 0; i < probe->requested; i++) {
		dispatch_group_enter(probe->group);
		dispatch_after_f(when, queue, &probe->items[i],
		    main_group_after_worker);
	}
	dispatch_group_notify_f(probe->group, dispatch_get_main_queue(), probe,
	    main_group_notify_worker);
}

static void
pressure_high_worker(void *ctx)
{
	struct dispatch_probe_state *state;

	state = ctx;
	record_common(state);
	__atomic_add_fetch(&state->high_started, 1, __ATOMIC_SEQ_CST);
	sleep_millis(state->high_sleep_ms);
	__atomic_add_fetch(&state->high_completed, 1, __ATOMIC_SEQ_CST);
}

static void
pressure_default_worker(void *ctx)
{
	struct dispatch_probe_state *state;
	uint32_t inflight;

	state = ctx;
	record_common(state);
	__atomic_add_fetch(&state->default_started, 1, __ATOMIC_SEQ_CST);
	inflight = __atomic_add_fetch(&state->default_inflight, 1,
	    __ATOMIC_SEQ_CST);
	update_max(&state->default_max_inflight, inflight);
	sleep_millis(state->sleep_ms);
	__atomic_sub_fetch(&state->default_inflight, 1, __ATOMIC_SEQ_CST);
	__atomic_add_fetch(&state->default_completed, 1, __ATOMIC_SEQ_CST);
}

static int
run_basic_mode_with_queue(const char *mode, struct dispatch_probe_state *state,
    dispatch_queue_t queue, uint32_t requested, uint32_t timeout_ms,
    int features)
{
	dispatch_group_t group;
	dispatch_time_t deadline;
	uint32_t completed, max_inflight, main_thread_callbacks, started;
	uint32_t unique_threads;
	int i, wait_rc;
	bool timed_out;

	group = dispatch_group_create();
	for (i = 0; i < (int)requested; i++)
		dispatch_group_async_f(group, queue, state, basic_worker);

	deadline = dispatch_time(DISPATCH_TIME_NOW,
	    (int64_t)timeout_ms * 1000000LL);
	wait_rc = dispatch_group_wait(group, deadline);
	timed_out = (wait_rc != 0);

	started = __atomic_load_n(&state->started, __ATOMIC_SEQ_CST);
	completed = __atomic_load_n(&state->completed, __ATOMIC_SEQ_CST);
	max_inflight = __atomic_load_n(&state->max_inflight, __ATOMIC_SEQ_CST);
	main_thread_callbacks = __atomic_load_n(&state->main_thread_callbacks,
	    __ATOMIC_SEQ_CST);
	unique_threads = unique_thread_count(state);

	emit_basic_result(
	    mode, (!timed_out && completed == requested) ? "ok" : "error",
	    wait_rc,
	    requested, started, completed, unique_threads, max_inflight,
	    main_thread_callbacks, timed_out, features);
	dispatch_release(group);
	return (!timed_out && completed == requested ? 0 : 1);
}

static int
run_basic_mode(struct dispatch_probe_state *state, uint32_t requested,
    uint32_t timeout_ms, int features)
{
	dispatch_queue_t queue;

	queue = dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0);
	return (run_basic_mode_with_queue("basic", state, queue, requested,
	    timeout_ms, features));
}

static dispatch_queue_t
create_executor_queue(dispatch_qos_class_t qos,
    enum dispatch_executor_queue_width_mode width_mode)
{
	dispatch_queue_attr_t attr;
	dispatch_queue_t queue;
	long logical_cpus;

	attr = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_CONCURRENT,
	    qos, 0);
	queue = dispatch_queue_create("twq.swift.executor", attr);
	switch (width_mode) {
	case DISPATCH_EXECUTOR_QUEUE_WIDTH_ASYNC_LOGICAL:
		dispatch_queue_set_width(queue,
		    DISPATCH_QUEUE_WIDTH_MAX_LOGICAL_CPUS);
		break;
	case DISPATCH_EXECUTOR_QUEUE_WIDTH_DEFAULT:
		break;
	case DISPATCH_EXECUTOR_QUEUE_WIDTH_SYNC_LOGICAL:
		logical_cpus = sysconf(_SC_NPROCESSORS_ONLN);
		if (logical_cpus < 1)
			logical_cpus = 1;
		dispatch_queue_set_width(queue, logical_cpus);
		break;
	}
	return (queue);
}

static void
executor_queue_noop(void *ctxt __unused)
{
}

static void
settle_executor_queue(dispatch_queue_t queue)
{
	dispatch_barrier_sync_f(queue, NULL, executor_queue_noop);
}

static int
run_executor_mode(struct dispatch_probe_state *state, uint32_t requested,
    uint32_t timeout_ms, int features)
{
	dispatch_group_t group;
	dispatch_queue_t queue;
	dispatch_time_t deadline;
	uint32_t completed, main_thread_callbacks, max_inflight, started;
	uint32_t unique_threads;
	int i, rc, wait_rc;
	bool timed_out;

	group = dispatch_group_create();
	queue = create_executor_queue(QOS_CLASS_DEFAULT,
	    DISPATCH_EXECUTOR_QUEUE_WIDTH_ASYNC_LOGICAL);
	state->group = group;

	for (i = 0; i < (int)requested; i++) {
		dispatch_group_enter(group);
		dispatch_async_f(queue, state, basic_leave_worker);
	}

	deadline = dispatch_time(DISPATCH_TIME_NOW,
	    (int64_t)timeout_ms * 1000000LL);
	wait_rc = dispatch_group_wait(group, deadline);
	timed_out = (wait_rc != 0);

	started = __atomic_load_n(&state->started, __ATOMIC_SEQ_CST);
	completed = __atomic_load_n(&state->completed, __ATOMIC_SEQ_CST);
	max_inflight = __atomic_load_n(&state->max_inflight, __ATOMIC_SEQ_CST);
	main_thread_callbacks = __atomic_load_n(&state->main_thread_callbacks,
	    __ATOMIC_SEQ_CST);
	unique_threads = unique_thread_count(state);
	rc = (!timed_out && completed == requested) ? 0 : wait_rc;

	emit_basic_result(
	    "executor",
	    (!timed_out && completed == requested) ? "ok" : "error",
	    rc, requested, started, completed, unique_threads, max_inflight,
	    main_thread_callbacks, timed_out, features);
	state->group = NULL;
	dispatch_release(queue);
	dispatch_release(group);
	return (!timed_out && completed == requested ? 0 : 1);
}

static int
run_after_mode_with_queue(const char *mode, struct dispatch_probe_state *state,
    dispatch_queue_t queue, uint32_t requested, uint32_t delay_ms,
    uint32_t timeout_ms, int features)
{
	dispatch_group_t group;
	dispatch_time_t deadline, when;
	uint32_t completed, main_thread_callbacks, max_inflight, started;
	uint32_t unique_threads;
	int i, rc, wait_rc;
	bool timed_out;

	group = dispatch_group_create();
	state->group = group;
	when = dispatch_time(DISPATCH_TIME_NOW, (int64_t)delay_ms * 1000000LL);

	for (i = 0; i < (int)requested; i++) {
		dispatch_group_enter(group);
		dispatch_after_f(when, queue, state, after_worker);
	}

	deadline = dispatch_time(DISPATCH_TIME_NOW,
	    (int64_t)timeout_ms * 1000000LL);
	wait_rc = dispatch_group_wait(group, deadline);
	timed_out = (wait_rc != 0);

	started = __atomic_load_n(&state->started, __ATOMIC_SEQ_CST);
	completed = __atomic_load_n(&state->completed, __ATOMIC_SEQ_CST);
	max_inflight = __atomic_load_n(&state->max_inflight, __ATOMIC_SEQ_CST);
	main_thread_callbacks = __atomic_load_n(&state->main_thread_callbacks,
	    __ATOMIC_SEQ_CST);
	unique_threads = unique_thread_count(state);
	rc = (!timed_out && completed == requested) ? 0 : wait_rc;

	emit_after_result(
	    mode, (!timed_out && completed == requested) ? "ok" : "error",
	    rc, requested, delay_ms, started, completed, unique_threads,
	    max_inflight, main_thread_callbacks, timed_out, features);
	state->group = NULL;
	dispatch_release(group);
	return (!timed_out && completed == requested ? 0 : 1);
}

static int
run_after_mode(struct dispatch_probe_state *state, uint32_t requested,
    uint32_t delay_ms, uint32_t timeout_ms, int features)
{
	dispatch_queue_t queue;

	queue = dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0);
	return (run_after_mode_with_queue("after", state, queue, requested,
	    delay_ms, timeout_ms, features));
}

static int
run_executor_after_mode(struct dispatch_probe_state *state, uint32_t requested,
    uint32_t delay_ms, uint32_t timeout_ms, int features)
{
	dispatch_queue_t queue;
	int rc;

	queue = create_executor_queue(QOS_CLASS_DEFAULT,
	    DISPATCH_EXECUTOR_QUEUE_WIDTH_ASYNC_LOGICAL);
	rc = run_after_mode_with_queue("executor-after", state, queue, requested,
	    delay_ms, timeout_ms, features);
	dispatch_release(queue);
	return (rc);
}

static int
run_executor_after_default_width_mode(struct dispatch_probe_state *state,
    uint32_t requested, uint32_t delay_ms, uint32_t timeout_ms, int features)
{
	dispatch_queue_t queue;
	int rc;

	queue = create_executor_queue(QOS_CLASS_DEFAULT,
	    DISPATCH_EXECUTOR_QUEUE_WIDTH_DEFAULT);
	rc = run_after_mode_with_queue("executor-after-default-width", state,
	    queue, requested, delay_ms, timeout_ms, features);
	dispatch_release(queue);
	return (rc);
}

static int
run_executor_after_sync_width_mode(struct dispatch_probe_state *state,
    uint32_t requested, uint32_t delay_ms, uint32_t timeout_ms, int features)
{
	dispatch_queue_t queue;
	int rc;

	queue = create_executor_queue(QOS_CLASS_DEFAULT,
	    DISPATCH_EXECUTOR_QUEUE_WIDTH_SYNC_LOGICAL);
	rc = run_after_mode_with_queue("executor-after-sync-width", state, queue,
	    requested, delay_ms, timeout_ms, features);
	dispatch_release(queue);
	return (rc);
}

static int
run_executor_after_settled_mode(struct dispatch_probe_state *state,
    uint32_t requested, uint32_t delay_ms, uint32_t timeout_ms, int features)
{
	dispatch_queue_t queue;
	int rc;

	queue = create_executor_queue(QOS_CLASS_DEFAULT,
	    DISPATCH_EXECUTOR_QUEUE_WIDTH_ASYNC_LOGICAL);
	settle_executor_queue(queue);
	rc = run_after_mode_with_queue("executor-after-settled", state, queue,
	    requested, delay_ms, timeout_ms, features);
	dispatch_release(queue);
	return (rc);
}

static void repeat_child_worker(void *ctx);
static void
repeat_parent_worker(void *ctx);

static void
schedule_repeat_parent(struct dispatch_repeat_probe *probe)
{

	if (__atomic_exchange_n(&probe->parent_scheduled, 1,
	    __ATOMIC_SEQ_CST) == 0) {
		dispatch_async_f(probe->executor_queue, probe, repeat_parent_worker);
	}
}

static void
start_repeat_round(struct dispatch_repeat_probe *probe)
{
	dispatch_time_t when;
	uint32_t i;

	probe->round_start_sysctl_error = read_twq_round_counters(
	    &probe->round_start_counters);
	printf("{\"kind\":\"dispatch-probe\",\"status\":\"progress\",\"data\":{"
	    "\"mode\":\"%s\",\"phase\":\"round-start\",\"round\":%u,"
	    "\"completed_rounds\":%u},"
	    "\"meta\":{\"component\":\"c\",\"binary\":\"twq-dispatch-probe\"}}\n",
	    probe->mode, probe->current_round, probe->completed_rounds);
	if (probe->round_start_sysctl_error == 0) {
		printf("{\"kind\":\"dispatch-probe\",\"status\":\"progress\",\"data\":{"
		    "\"mode\":\"%s\",\"phase\":\"round-start-counters\","
		    "\"round\":%u,\"completed_rounds\":%u,"
		    "\"reqthreads_count\":%u,\"thread_enter_count\":%u,"
		    "\"thread_return_count\":%u,\"bucket_total\":%u,"
		    "\"bucket_idle\":%u,\"bucket_active\":%u},"
		    "\"meta\":{\"component\":\"c\",\"binary\":\"twq-dispatch-probe\"}}\n",
		    probe->mode, probe->current_round, probe->completed_rounds,
		    probe->round_start_counters.reqthreads_count,
		    probe->round_start_counters.thread_enter_count,
		    probe->round_start_counters.thread_return_count,
		    probe->round_start_counters.bucket_total,
		    probe->round_start_counters.bucket_idle,
		    probe->round_start_counters.bucket_active);
	} else {
		printf("{\"kind\":\"dispatch-probe\",\"status\":\"progress\",\"data\":{"
		    "\"mode\":\"%s\",\"phase\":\"round-start-counters\","
		    "\"round\":%u,\"completed_rounds\":%u,\"sysctl_error\":%d},"
		    "\"meta\":{\"component\":\"c\",\"binary\":\"twq-dispatch-probe\"}}\n",
		    probe->mode, probe->current_round, probe->completed_rounds,
		    probe->round_start_sysctl_error);
	}
	fflush(stdout);

	probe->current_task = 0;
	probe->round_sum = 0;
	when = dispatch_time(DISPATCH_TIME_NOW,
	    (int64_t)probe->delay_ms * 1000000LL);
	for (i = 0; i < probe->tasks; i++) {
		probe->children[i].probe = probe;
		probe->children[i].task = i;
		__atomic_store_n(&probe->children[i].done, 0, __ATOMIC_RELEASE);
		dispatch_after_f(when, probe->timer_queue, &probe->children[i],
		    repeat_child_worker);
	}
}

static void
repeat_finish_ok(struct dispatch_repeat_probe *probe)
{
	struct dispatch_probe_state *state;
	uint32_t completed, main_thread_callbacks, max_inflight, started;
	uint32_t unique_threads;

	state = probe->state;
	started = __atomic_load_n(&state->started, __ATOMIC_SEQ_CST);
	completed = __atomic_load_n(&state->completed, __ATOMIC_SEQ_CST);
	max_inflight = __atomic_load_n(&state->max_inflight, __ATOMIC_SEQ_CST);
	main_thread_callbacks = __atomic_load_n(&state->main_thread_callbacks,
	    __ATOMIC_SEQ_CST);
	unique_threads = unique_thread_count(state);

	emit_repeat_result(probe->mode, "ok", 0, probe->rounds, probe->tasks,
	    probe->delay_ms, probe->completed_rounds, probe->total_sum,
	    probe->rounds * (probe->tasks * (probe->tasks - 1) / 2), started,
	    completed, unique_threads, max_inflight, main_thread_callbacks,
	    false, probe->features);
	exit(0);
}

static void
repeat_child_worker(void *ctx)
{
	struct dispatch_repeat_child *child;
	struct dispatch_repeat_probe *probe;
	struct dispatch_probe_state *state;
	uint32_t inflight;

	child = ctx;
	probe = child->probe;
	state = probe->state;
	__atomic_add_fetch(&state->started, 1, __ATOMIC_SEQ_CST);
	inflight = __atomic_add_fetch(&state->inflight, 1, __ATOMIC_SEQ_CST);
	update_max(&state->max_inflight, inflight);
	record_common(state);
	__atomic_store_n(&child->done, 1, __ATOMIC_RELEASE);
	__atomic_sub_fetch(&state->inflight, 1, __ATOMIC_SEQ_CST);
	__atomic_add_fetch(&state->completed, 1, __ATOMIC_SEQ_CST);
	schedule_repeat_parent(probe);
}

static void
repeat_parent_worker(void *ctx)
{
	struct dispatch_repeat_probe *probe;
	struct dispatch_repeat_child *child;
	struct dispatch_probe_state *state;
	struct dispatch_twq_round_counters round_end_counters;
	int round_end_sysctl_error;

	probe = ctx;
	state = probe->state;
	__atomic_store_n(&probe->parent_scheduled, 0, __ATOMIC_SEQ_CST);
	record_common(state);

	for (;;) {
		while (probe->current_task < probe->tasks) {
			child = &probe->children[probe->current_task];
			if (__atomic_load_n(&child->done, __ATOMIC_ACQUIRE) == 0)
				goto out;
			probe->round_sum += probe->current_task;
			probe->current_task++;
		}

		probe->completed_rounds++;
		probe->total_sum += probe->round_sum;
		round_end_sysctl_error = read_twq_round_counters(&round_end_counters);
		printf("{\"kind\":\"dispatch-probe\",\"status\":\"progress\",\"data\":{"
		    "\"mode\":\"%s\",\"phase\":\"round-ok\",\"round\":%u,"
		    "\"round_sum\":%u,\"expected_round_sum\":%u,"
		    "\"completed_rounds\":%u,\"total_sum\":%u},"
		    "\"meta\":{\"component\":\"c\",\"binary\":\"twq-dispatch-probe\"}}\n",
		    probe->mode, probe->current_round, probe->round_sum,
		    probe->tasks * (probe->tasks - 1) / 2, probe->completed_rounds,
		    probe->total_sum);
		if (probe->round_start_sysctl_error == 0 &&
		    round_end_sysctl_error == 0) {
			printf("{\"kind\":\"dispatch-probe\",\"status\":\"progress\",\"data\":{"
			    "\"mode\":\"%s\",\"phase\":\"round-ok-counters\","
			    "\"round\":%u,\"completed_rounds\":%u,"
			    "\"reqthreads_count\":%u,\"thread_enter_count\":%u,"
			    "\"thread_return_count\":%u,\"bucket_total\":%u,"
			    "\"bucket_idle\":%u,\"bucket_active\":%u,"
			    "\"reqthreads_delta\":%u,\"thread_enter_delta\":%u,"
			    "\"thread_return_delta\":%u},"
			    "\"meta\":{\"component\":\"c\",\"binary\":\"twq-dispatch-probe\"}}\n",
			    probe->mode, probe->current_round, probe->completed_rounds,
			    round_end_counters.reqthreads_count,
			    round_end_counters.thread_enter_count,
			    round_end_counters.thread_return_count,
			    round_end_counters.bucket_total,
			    round_end_counters.bucket_idle,
			    round_end_counters.bucket_active,
			    round_end_counters.reqthreads_count -
			    probe->round_start_counters.reqthreads_count,
			    round_end_counters.thread_enter_count -
			    probe->round_start_counters.thread_enter_count,
			    round_end_counters.thread_return_count -
			    probe->round_start_counters.thread_return_count);
		} else {
			printf("{\"kind\":\"dispatch-probe\",\"status\":\"progress\",\"data\":{"
			    "\"mode\":\"%s\",\"phase\":\"round-ok-counters\","
			    "\"round\":%u,\"completed_rounds\":%u,\"sysctl_error\":%d},"
			    "\"meta\":{\"component\":\"c\",\"binary\":\"twq-dispatch-probe\"}}\n",
			    probe->mode, probe->current_round, probe->completed_rounds,
			    probe->round_start_sysctl_error != 0 ?
			    probe->round_start_sysctl_error : round_end_sysctl_error);
		}
		fflush(stdout);

		probe->current_round++;
		if (probe->current_round >= probe->rounds)
			repeat_finish_ok(probe);
		start_repeat_round(probe);
	}

out:
	if (probe->current_round < probe->rounds &&
	    probe->current_task < probe->tasks &&
	    __atomic_load_n(&probe->children[probe->current_task].done,
	    __ATOMIC_ACQUIRE) != 0) {
		schedule_repeat_parent(probe);
	}
}

static void
repeat_root_worker(void *ctx)
{
	struct dispatch_repeat_probe *probe;

	probe = ctx;
	record_common(probe->state);
	start_repeat_round(probe);
}

static int
run_main_executor_after_repeat_mode(struct dispatch_probe_state *state,
    uint32_t rounds, uint32_t tasks, uint32_t delay_ms, int features)
{
	struct dispatch_repeat_probe probe;
	uint32_t expected_total_sum;

	if (rounds == 0 || tasks == 0) {
		expected_total_sum = rounds * (tasks * (tasks - 1) / 2);
		emit_repeat_result("main-executor-after-repeat", "ok", 0, rounds,
		    tasks, delay_ms, rounds, expected_total_sum, expected_total_sum,
		    0, 0, 0, 0, 0, false, features);
		return (0);
	}

	memset(&probe, 0, sizeof(probe));
	probe.state = state;
	probe.mode = "main-executor-after-repeat";
	probe.rounds = rounds;
	probe.tasks = tasks;
	probe.delay_ms = delay_ms;
	probe.timer_queue = dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0);
	probe.features = features;
	probe.children = calloc(tasks, sizeof(*probe.children));
	if (probe.children == NULL) {
		perror("calloc");
		emit_repeat_result("main-executor-after-repeat", "error", errno,
		    rounds, tasks, delay_ms, 0, 0,
		    rounds * (tasks * (tasks - 1) / 2), 0, 0, 0, 0, 0, false,
		    features);
		return (1);
	}

	probe.executor_queue = create_executor_queue(QOS_CLASS_DEFAULT,
	    DISPATCH_EXECUTOR_QUEUE_WIDTH_ASYNC_LOGICAL);
	settle_executor_queue(probe.executor_queue);

	printf("{\"kind\":\"dispatch-probe\",\"status\":\"progress\",\"data\":{"
	    "\"mode\":\"%s\",\"phase\":\"before-spawn\",\"rounds\":%u,"
	    "\"tasks\":%u,\"delay_ms\":%u},"
	    "\"meta\":{\"component\":\"c\",\"binary\":\"twq-dispatch-probe\"}}\n",
	    probe.mode, probe.rounds, probe.tasks, probe.delay_ms);
	fflush(stdout);

	dispatch_async_f(dispatch_get_main_queue(), &probe, repeat_root_worker);
	dispatch_main();
	return (1);
}

static void
resume_repeat_finish_ok(struct dispatch_resume_repeat_probe *probe)
{
	struct dispatch_probe_state *state;
	uint32_t completed, main_thread_callbacks, max_inflight, started;
	uint32_t unique_threads;

	state = probe->state;
	started = __atomic_load_n(&state->started, __ATOMIC_SEQ_CST);
	completed = __atomic_load_n(&state->completed, __ATOMIC_SEQ_CST);
	max_inflight = __atomic_load_n(&state->max_inflight, __ATOMIC_SEQ_CST);
	main_thread_callbacks = __atomic_load_n(&state->main_thread_callbacks,
	    __ATOMIC_SEQ_CST);
	unique_threads = unique_thread_count(state);

	emit_repeat_result(probe->mode, "ok", 0, probe->rounds, probe->tasks,
	    probe->delay_ms, probe->completed_rounds, probe->total_sum,
	    probe->rounds * (probe->tasks * (probe->tasks - 1) / 2), started,
	    completed, unique_threads, max_inflight, main_thread_callbacks,
	    false, probe->features);
	exit(0);
}

static void
resume_repeat_round_complete_worker(void *ctx);

static void
resume_repeat_resume_worker(void *ctx)
{
	struct dispatch_resume_repeat_child *child;
	struct dispatch_resume_repeat_probe *probe;
	struct dispatch_probe_state *state;
	uint32_t inflight;

	child = ctx;
	probe = child->probe;
	state = probe->state;
	__atomic_add_fetch(&state->started, 1, __ATOMIC_SEQ_CST);
	inflight = __atomic_add_fetch(&state->inflight, 1, __ATOMIC_SEQ_CST);
	update_max(&state->max_inflight, inflight);
	record_common(state);
	__atomic_add_fetch(&probe->round_sum, child->task, __ATOMIC_SEQ_CST);
	__atomic_sub_fetch(&state->inflight, 1, __ATOMIC_SEQ_CST);
	__atomic_add_fetch(&state->completed, 1, __ATOMIC_SEQ_CST);
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

	probe->round_start_sysctl_error = read_twq_round_counters(
	    &probe->round_start_counters);
	printf("{\"kind\":\"dispatch-probe\",\"status\":\"progress\",\"data\":{"
	    "\"mode\":\"%s\",\"phase\":\"round-start\",\"round\":%u,"
	    "\"completed_rounds\":%u},"
	    "\"meta\":{\"component\":\"c\",\"binary\":\"twq-dispatch-probe\"}}\n",
	    probe->mode, probe->current_round, probe->completed_rounds);
	if (probe->round_start_sysctl_error == 0) {
		printf("{\"kind\":\"dispatch-probe\",\"status\":\"progress\",\"data\":{"
		    "\"mode\":\"%s\",\"phase\":\"round-start-counters\","
		    "\"round\":%u,\"completed_rounds\":%u,"
		    "\"reqthreads_count\":%u,\"thread_enter_count\":%u,"
		    "\"thread_return_count\":%u,\"bucket_total\":%u,"
		    "\"bucket_idle\":%u,\"bucket_active\":%u},"
		    "\"meta\":{\"component\":\"c\",\"binary\":\"twq-dispatch-probe\"}}\n",
		    probe->mode, probe->current_round, probe->completed_rounds,
		    probe->round_start_counters.reqthreads_count,
		    probe->round_start_counters.thread_enter_count,
		    probe->round_start_counters.thread_return_count,
		    probe->round_start_counters.bucket_total,
		    probe->round_start_counters.bucket_idle,
		    probe->round_start_counters.bucket_active);
	} else {
		printf("{\"kind\":\"dispatch-probe\",\"status\":\"progress\",\"data\":{"
		    "\"mode\":\"%s\",\"phase\":\"round-start-counters\","
		    "\"round\":%u,\"completed_rounds\":%u,\"sysctl_error\":%d},"
		    "\"meta\":{\"component\":\"c\",\"binary\":\"twq-dispatch-probe\"}}\n",
		    probe->mode, probe->current_round, probe->completed_rounds,
		    probe->round_start_sysctl_error);
	}
	fflush(stdout);

	group = dispatch_group_create();
	probe->round_group = group;
	probe->round_sum = 0;
	when = dispatch_time(DISPATCH_TIME_NOW,
	    (int64_t)probe->delay_ms * 1000000LL);
	for (i = 0; i < probe->tasks; i++) {
		probe->children[i].probe = probe;
		probe->children[i].group = group;
		probe->children[i].task = i;
		probe->children[i].round = probe->current_round;
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
	struct dispatch_twq_round_counters round_end_counters;
	uint32_t expected_round_sum;
	uint32_t main_thread_callbacks, max_inflight, started, completed;
	uint32_t unique_threads;
	int round_end_sysctl_error;

	probe = ctx;
	expected_round_sum = probe->tasks * (probe->tasks - 1) / 2;
	record_common(probe->state);
	probe->completed_rounds++;
	probe->total_sum += probe->round_sum;
	round_end_sysctl_error = read_twq_round_counters(&round_end_counters);

	printf("{\"kind\":\"dispatch-probe\",\"status\":\"progress\",\"data\":{"
	    "\"mode\":\"%s\",\"phase\":\"round-ok\",\"round\":%u,"
	    "\"round_sum\":%u,\"expected_round_sum\":%u,"
	    "\"completed_rounds\":%u,\"total_sum\":%u},"
	    "\"meta\":{\"component\":\"c\",\"binary\":\"twq-dispatch-probe\"}}\n",
	    probe->mode, probe->current_round, probe->round_sum,
	    expected_round_sum, probe->completed_rounds, probe->total_sum);
	if (probe->round_start_sysctl_error == 0 && round_end_sysctl_error == 0) {
		printf("{\"kind\":\"dispatch-probe\",\"status\":\"progress\",\"data\":{"
		    "\"mode\":\"%s\",\"phase\":\"round-ok-counters\","
		    "\"round\":%u,\"completed_rounds\":%u,"
		    "\"reqthreads_count\":%u,\"thread_enter_count\":%u,"
		    "\"thread_return_count\":%u,\"bucket_total\":%u,"
		    "\"bucket_idle\":%u,\"bucket_active\":%u,"
		    "\"reqthreads_delta\":%u,\"thread_enter_delta\":%u,"
		    "\"thread_return_delta\":%u},"
		    "\"meta\":{\"component\":\"c\",\"binary\":\"twq-dispatch-probe\"}}\n",
		    probe->mode, probe->current_round, probe->completed_rounds,
		    round_end_counters.reqthreads_count,
		    round_end_counters.thread_enter_count,
		    round_end_counters.thread_return_count,
		    round_end_counters.bucket_total,
		    round_end_counters.bucket_idle,
		    round_end_counters.bucket_active,
		    round_end_counters.reqthreads_count -
		    probe->round_start_counters.reqthreads_count,
		    round_end_counters.thread_enter_count -
		    probe->round_start_counters.thread_enter_count,
		    round_end_counters.thread_return_count -
		    probe->round_start_counters.thread_return_count);
	} else {
		printf("{\"kind\":\"dispatch-probe\",\"status\":\"progress\",\"data\":{"
		    "\"mode\":\"%s\",\"phase\":\"round-ok-counters\","
		    "\"round\":%u,\"completed_rounds\":%u,\"sysctl_error\":%d},"
		    "\"meta\":{\"component\":\"c\",\"binary\":\"twq-dispatch-probe\"}}\n",
		    probe->mode, probe->current_round, probe->completed_rounds,
		    probe->round_start_sysctl_error != 0 ?
		    probe->round_start_sysctl_error : round_end_sysctl_error);
	}
	fflush(stdout);

	dispatch_release(probe->round_group);
	probe->round_group = NULL;
	if (probe->round_sum != expected_round_sum) {
		started = __atomic_load_n(&probe->state->started, __ATOMIC_SEQ_CST);
		completed = __atomic_load_n(&probe->state->completed,
		    __ATOMIC_SEQ_CST);
		max_inflight = __atomic_load_n(&probe->state->max_inflight,
		    __ATOMIC_SEQ_CST);
		main_thread_callbacks = __atomic_load_n(
		    &probe->state->main_thread_callbacks, __ATOMIC_SEQ_CST);
		unique_threads = unique_thread_count(probe->state);
		emit_repeat_result(probe->mode, "error", EPROTO, probe->rounds,
		    probe->tasks, probe->delay_ms, probe->completed_rounds,
		    probe->total_sum, probe->rounds * expected_round_sum, started,
		    completed, unique_threads, max_inflight, main_thread_callbacks,
		    false, probe->features);
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
	record_common(probe->state);
	resume_repeat_start_round(probe);
}

static int
run_main_executor_resume_repeat_mode(struct dispatch_probe_state *state,
    uint32_t rounds, uint32_t tasks, uint32_t delay_ms, int features)
{
	struct dispatch_resume_repeat_probe probe;
	uint32_t expected_total_sum;

	if (rounds == 0 || tasks == 0) {
		expected_total_sum = rounds * (tasks * (tasks - 1) / 2);
		emit_repeat_result("main-executor-resume-repeat", "ok", 0, rounds,
		    tasks, delay_ms, rounds, expected_total_sum, expected_total_sum,
		    0, 0, 0, 0, 0, false, features);
		return (0);
	}

	memset(&probe, 0, sizeof(probe));
	probe.state = state;
	probe.mode = "main-executor-resume-repeat";
	probe.rounds = rounds;
	probe.tasks = tasks;
	probe.delay_ms = delay_ms;
	probe.timer_queue = dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0);
	probe.features = features;
	probe.children = calloc(tasks, sizeof(*probe.children));
	if (probe.children == NULL) {
		perror("calloc");
		emit_repeat_result("main-executor-resume-repeat", "error", errno,
		    rounds, tasks, delay_ms, 0, 0,
		    rounds * (tasks * (tasks - 1) / 2), 0, 0, 0, 0, 0, false,
		    features);
		return (1);
	}

	probe.executor_queue = create_executor_queue(QOS_CLASS_DEFAULT,
	    DISPATCH_EXECUTOR_QUEUE_WIDTH_ASYNC_LOGICAL);
	settle_executor_queue(probe.executor_queue);

	printf("{\"kind\":\"dispatch-probe\",\"status\":\"progress\",\"data\":{"
	    "\"mode\":\"%s\",\"phase\":\"before-spawn\",\"rounds\":%u,"
	    "\"tasks\":%u,\"delay_ms\":%u},"
	    "\"meta\":{\"component\":\"c\",\"binary\":\"twq-dispatch-probe\"}}\n",
	    probe.mode, probe.rounds, probe.tasks, probe.delay_ms);
	fflush(stdout);

	dispatch_async_f(dispatch_get_main_queue(), &probe,
	    resume_repeat_root_worker);
	dispatch_main();
	return (1);
}

static void
after_group_root_worker(void *ctx)
{
	struct dispatch_after_group_probe *probe;
	struct dispatch_probe_state *state;
	dispatch_group_t group;
	dispatch_queue_t queue;
	dispatch_time_t deadline, when;
	uint32_t completed, main_thread_callbacks, max_inflight, started;
	uint32_t unique_threads;
	int i, rc, wait_rc;
	bool timed_out;

	probe = ctx;
	state = probe->state;
	record_common(state);
	group = dispatch_group_create();
	queue = dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0);
	when = dispatch_time(DISPATCH_TIME_NOW,
	    (int64_t)probe->delay_ms * 1000000LL);
	deadline = dispatch_time(DISPATCH_TIME_NOW,
	    (int64_t)probe->timeout_ms * 1000000LL);

	state->group = group;
	for (i = 0; i < (int)probe->requested; i++) {
		dispatch_group_enter(group);
		dispatch_after_f(when, queue, state, after_worker);
	}

	wait_rc = dispatch_group_wait(group, deadline);
	timed_out = (wait_rc != 0);
	started = __atomic_load_n(&state->started, __ATOMIC_SEQ_CST);
	completed = __atomic_load_n(&state->completed, __ATOMIC_SEQ_CST);
	max_inflight = __atomic_load_n(&state->max_inflight, __ATOMIC_SEQ_CST);
	main_thread_callbacks = __atomic_load_n(&state->main_thread_callbacks,
	    __ATOMIC_SEQ_CST);
	unique_threads = unique_thread_count(state);
	rc = (!timed_out && completed == probe->requested) ? 0 : wait_rc;

	emit_after_result(
	    probe->mode,
	    (!timed_out && completed == probe->requested) ? "ok" : "error",
	    rc, probe->requested, probe->delay_ms, started, completed,
	    unique_threads, max_inflight, main_thread_callbacks, timed_out,
	    probe->features);

	state->group = NULL;
	dispatch_release(group);
	__atomic_store_n(&probe->rc,
	    (!timed_out && completed == probe->requested) ? 0 : 1,
	    __ATOMIC_SEQ_CST);
	dispatch_semaphore_signal(probe->done);
}

static int
run_worker_after_group_mode(struct dispatch_probe_state *state,
    uint32_t requested, uint32_t delay_ms, uint32_t timeout_ms, int features)
{
	struct dispatch_after_group_probe probe;
	dispatch_time_t deadline;
	dispatch_queue_t queue;
	uint32_t completed, main_thread_callbacks, max_inflight, started;
	uint32_t unique_threads;
	int wait_rc;

	memset(&probe, 0, sizeof(probe));
	probe.state = state;
	probe.mode = "worker-after-group";
	probe.requested = requested;
	probe.delay_ms = delay_ms;
	probe.timeout_ms = timeout_ms;
	probe.features = features;
	probe.done = dispatch_semaphore_create(0);
	queue = dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0);
	dispatch_async_f(queue, &probe, after_group_root_worker);

	deadline = dispatch_time(DISPATCH_TIME_NOW,
	    (int64_t)(timeout_ms + delay_ms + 1000U) * 1000000LL);
	wait_rc = dispatch_semaphore_wait(probe.done, deadline);
	if (wait_rc != 0) {
		started = __atomic_load_n(&state->started, __ATOMIC_SEQ_CST);
		completed = __atomic_load_n(&state->completed, __ATOMIC_SEQ_CST);
		max_inflight = __atomic_load_n(&state->max_inflight,
		    __ATOMIC_SEQ_CST);
		main_thread_callbacks = __atomic_load_n(
		    &state->main_thread_callbacks, __ATOMIC_SEQ_CST);
		unique_threads = unique_thread_count(state);
		emit_after_result("worker-after-group", "error", wait_rc, requested,
		    delay_ms, started, completed, unique_threads, max_inflight,
		    main_thread_callbacks, true, features);
		dispatch_release(probe.done);
		return (1);
	}

	dispatch_release(probe.done);
	return (__atomic_load_n(&probe.rc, __ATOMIC_SEQ_CST));
}

static int
run_main_mode_with_queue(const char *mode, struct dispatch_probe_state *state,
    dispatch_queue_t queue, uint32_t requested, uint32_t delay_ms,
    int features, bool timed)
{
	struct dispatch_main_probe probe;
	dispatch_time_t when;
	int i;

	if (requested == 0) {
		if (timed) {
			emit_after_result(mode, "ok", 0, requested, delay_ms, 0, 0, 0,
			    0, 0, false, features);
		} else {
			emit_basic_result(mode, "ok", 0, requested, 0, 0, 0, 0, 0,
			    false, features);
		}
		return (0);
	}

	memset(&probe, 0, sizeof(probe));
	probe.state = state;
	probe.mode = mode;
	probe.requested = requested;
	probe.delay_ms = delay_ms;
	probe.features = features;
	probe.timed = timed;
	when = dispatch_time(DISPATCH_TIME_NOW, (int64_t)delay_ms * 1000000LL);

	for (i = 0; i < (int)requested; i++) {
		if (timed)
			dispatch_after_f(when, queue, &probe, main_queue_exit_worker);
		else
			dispatch_async_f(queue, &probe, main_queue_exit_worker);
	}

	dispatch_main();
	return (1);
}

static int
run_main_mode(struct dispatch_probe_state *state, uint32_t requested,
    int features)
{
	return (run_main_mode_with_queue("main", state, dispatch_get_main_queue(),
	    requested, 0, features, false));
}

static int
run_main_after_mode(struct dispatch_probe_state *state, uint32_t requested,
    uint32_t delay_ms, int features)
{
	return (run_main_mode_with_queue("main-after", state,
	    dispatch_get_main_queue(), requested, delay_ms, features, true));
}

static int
run_main_roundtrip_after_mode(struct dispatch_probe_state *state,
    uint32_t requested, uint32_t delay_ms, int features)
{
	struct dispatch_main_roundtrip_probe probe;
	uint32_t i;

	if (requested == 0) {
		emit_after_result("main-roundtrip-after", "ok", 0, 0, delay_ms,
		    0, 0, 0, 0, 0, false, features);
		return (0);
	}

	memset(&probe, 0, sizeof(probe));
	probe.state = state;
	probe.mode = "main-roundtrip-after";
	probe.requested = requested;
	probe.delay_ms = delay_ms;
	probe.features = features;
	probe.items = calloc(requested, sizeof(*probe.items));
	if (probe.items == NULL) {
		perror("calloc");
		return (1);
	}
	for (i = 0; i < requested; i++)
		probe.items[i].probe = &probe;

	dispatch_async_f(dispatch_get_main_queue(), &probe,
	    main_roundtrip_root_worker);
	dispatch_main();
	return (1);
}

static int
run_main_group_after_mode(struct dispatch_probe_state *state,
    uint32_t requested, uint32_t delay_ms, int features)
{
	struct dispatch_main_group_probe probe;
	uint32_t i;

	if (requested == 0) {
		emit_after_result("main-group-after", "ok", 0, 0, delay_ms, 0,
		    0, 0, 0, 0, false, features);
		return (0);
	}

	memset(&probe, 0, sizeof(probe));
	probe.state = state;
	probe.mode = "main-group-after";
	probe.requested = requested;
	probe.delay_ms = delay_ms;
	probe.features = features;
	probe.group = dispatch_group_create();
	probe.items = calloc(requested, sizeof(*probe.items));
	if (probe.group == NULL || probe.items == NULL) {
		if (probe.group != NULL)
			dispatch_release(probe.group);
		free(probe.items);
		perror("dispatch_group_create");
		return (1);
	}
	for (i = 0; i < requested; i++)
		probe.items[i].probe = &probe;

	dispatch_async_f(dispatch_get_main_queue(), &probe, main_group_root_worker);
	dispatch_main();
	return (1);
}

static int
run_pressure_mode(struct dispatch_probe_state *state, uint32_t requested_default,
    uint32_t requested_high, uint32_t timeout_ms, int features)
{
	dispatch_group_t group;
	dispatch_queue_t default_queue, high_queue;
	dispatch_time_t deadline;
	uint32_t completed_default, completed_high, default_max_inflight;
	uint32_t main_thread_callbacks, started_default, started_high;
	uint32_t unique_threads;
	int i, rc, wait_rc;
	bool high_ready, timed_out;

	group = dispatch_group_create();
	high_queue = dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0);
	default_queue = dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0);

	for (i = 0; i < (int)requested_high; i++)
		dispatch_group_async_f(group, high_queue, state, pressure_high_worker);

	high_ready = wait_for_counter(&state->high_started, requested_high,
	    MIN(timeout_ms, 1000));
	if (high_ready) {
		for (i = 0; i < (int)requested_default; i++) {
			dispatch_group_async_f(group, default_queue, state,
			    pressure_default_worker);
		}
	}

	deadline = dispatch_time(DISPATCH_TIME_NOW,
	    (int64_t)timeout_ms * 1000000LL);
	wait_rc = dispatch_group_wait(group, deadline);
	timed_out = (wait_rc != 0) || !high_ready;
	rc = high_ready ? wait_rc : ETIMEDOUT;

	started_high = __atomic_load_n(&state->high_started, __ATOMIC_SEQ_CST);
	completed_high = __atomic_load_n(&state->high_completed, __ATOMIC_SEQ_CST);
	started_default = __atomic_load_n(&state->default_started,
	    __ATOMIC_SEQ_CST);
	completed_default = __atomic_load_n(&state->default_completed,
	    __ATOMIC_SEQ_CST);
	default_max_inflight = __atomic_load_n(&state->default_max_inflight,
	    __ATOMIC_SEQ_CST);
	main_thread_callbacks = __atomic_load_n(&state->main_thread_callbacks,
	    __ATOMIC_SEQ_CST);
	unique_threads = unique_thread_count(state);

	emit_pressure_result(
	    (!timed_out && completed_default == requested_default &&
	    completed_high == requested_high) ? "ok" : "error",
	    rc, requested_default, requested_high, started_default,
	    completed_default, started_high, completed_high, unique_threads,
	    default_max_inflight, main_thread_callbacks, timed_out, features);
	dispatch_release(group);
	return (!timed_out && completed_default == requested_default &&
	    completed_high == requested_high ? 0 : 1);
}

static int
run_burst_mode(const char *mode, struct dispatch_probe_state *state,
    uint32_t requested, uint32_t rounds, uint32_t pause_ms,
    uint32_t settle_ms, uint32_t timeout_ms, bool expect_reuse, int features)
{
	dispatch_group_t group;
	dispatch_queue_t queue;
	dispatch_time_t deadline;
	uint32_t completed, max_inflight, main_thread_callbacks, rounds_completed;
	uint32_t round_unique_threads[DISPATCH_PROBE_MAX_ROUNDS];
	uint32_t round_new_threads[DISPATCH_PROBE_MAX_ROUNDS];
	uint32_t round_rest_total[DISPATCH_PROBE_MAX_ROUNDS];
	uint32_t round_rest_idle[DISPATCH_PROBE_MAX_ROUNDS];
	uint32_t round_rest_active[DISPATCH_PROBE_MAX_ROUNDS];
	uint32_t round_thread_enter_delta[DISPATCH_PROBE_MAX_ROUNDS];
	uint32_t round_reqthreads_delta[DISPATCH_PROBE_MAX_ROUNDS];
	uint32_t round_should_narrow_true_delta[DISPATCH_PROBE_MAX_ROUNDS];
	uint32_t after_reqthreads_count, after_should_narrow_true_count;
	uint32_t after_thread_enter_count, before_reqthreads_count;
	uint32_t before_should_narrow_true_count, before_thread_enter_count;
	uint32_t settled_total, settled_idle, settled_active;
	uint32_t started, unique_after, unique_before, unique_threads, warm_floor;
	int i, rc, wait_rc, sysctl_error;
	bool plateau_ok, reuse_ok, settled_ok;
	bool timed_out;

	memset(round_unique_threads, 0, sizeof(round_unique_threads));
	memset(round_new_threads, 0, sizeof(round_new_threads));
	memset(round_rest_total, 0, sizeof(round_rest_total));
	memset(round_rest_idle, 0, sizeof(round_rest_idle));
	memset(round_rest_active, 0, sizeof(round_rest_active));
	memset(round_thread_enter_delta, 0, sizeof(round_thread_enter_delta));
	memset(round_reqthreads_delta, 0, sizeof(round_reqthreads_delta));
	memset(round_should_narrow_true_delta, 0,
	    sizeof(round_should_narrow_true_delta));
	settled_total = 0;
	settled_idle = 0;
	settled_active = 0;
	rounds_completed = 0;
	rc = 0;
	sysctl_error = 0;
	timed_out = false;
	warm_floor = dispatch_warm_floor();

	if (rounds == 0 || rounds > DISPATCH_PROBE_MAX_ROUNDS) {
		fprintf(stderr, "invalid rounds: %u\n", rounds);
		return (64);
	}

	queue = dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0);
	for (i = 0; i < (int)rounds; i++) {
		group = dispatch_group_create();
		unique_before = unique_thread_count(state);
		sysctl_error = read_sysctl_u32_text("kern.twq.thread_enter_count",
		    &before_thread_enter_count);
		if (sysctl_error == 0) {
			sysctl_error = read_sysctl_u32_text("kern.twq.reqthreads_count",
			    &before_reqthreads_count);
		}
		if (sysctl_error == 0) {
			sysctl_error = read_sysctl_u32_text(
			    "kern.twq.should_narrow_true_count",
			    &before_should_narrow_true_count);
		}
		if (sysctl_error != 0) {
			rc = sysctl_error;
			dispatch_release(group);
			break;
		}
		for (int j = 0; j < (int)requested; j++)
			dispatch_group_async_f(group, queue, state, basic_worker);

		deadline = dispatch_time(DISPATCH_TIME_NOW,
		    (int64_t)timeout_ms * 1000000LL);
		wait_rc = dispatch_group_wait(group, deadline);
		dispatch_release(group);
		if (wait_rc != 0) {
			timed_out = true;
			rc = wait_rc;
			break;
		}

		rounds_completed++;
		sleep_millis(pause_ms);
		unique_after = unique_thread_count(state);
		round_unique_threads[i] = unique_after;
		round_new_threads[i] = unique_after - unique_before;
		sysctl_error = read_sysctl_u32_text("kern.twq.thread_enter_count",
		    &after_thread_enter_count);
		if (sysctl_error == 0) {
			sysctl_error = read_sysctl_u32_text("kern.twq.reqthreads_count",
			    &after_reqthreads_count);
		}
		if (sysctl_error == 0) {
			sysctl_error = read_sysctl_u32_text(
			    "kern.twq.should_narrow_true_count",
			    &after_should_narrow_true_count);
		}
		if (sysctl_error == 0) {
			round_thread_enter_delta[i] = after_thread_enter_count -
			    before_thread_enter_count;
			round_reqthreads_delta[i] = after_reqthreads_count -
			    before_reqthreads_count;
			round_should_narrow_true_delta[i] =
			    after_should_narrow_true_count -
			    before_should_narrow_true_count;
		}
		if (sysctl_error != 0) {
			rc = sysctl_error;
			break;
		}
		sysctl_error = read_bucket_sums(&round_rest_total[i],
		    &round_rest_idle[i], &round_rest_active[i]);
		if (sysctl_error != 0) {
			rc = sysctl_error;
			break;
		}
	}

	if (!timed_out && sysctl_error == 0) {
		sleep_millis(settle_ms);
		sysctl_error = read_bucket_sums(&settled_total, &settled_idle,
		    &settled_active);
		if (sysctl_error != 0)
			rc = sysctl_error;
	}

	started = __atomic_load_n(&state->started, __ATOMIC_SEQ_CST);
	completed = __atomic_load_n(&state->completed, __ATOMIC_SEQ_CST);
	max_inflight = __atomic_load_n(&state->max_inflight, __ATOMIC_SEQ_CST);
	main_thread_callbacks = __atomic_load_n(&state->main_thread_callbacks,
	    __ATOMIC_SEQ_CST);
	unique_threads = unique_thread_count(state);
	reuse_ok = true;
	plateau_ok = true;
	for (i = 1; i < (int)rounds_completed; i++) {
		if (round_new_threads[i] != 0)
			reuse_ok = false;
	}
	for (i = 0; i < (int)rounds_completed; i++) {
		if (round_rest_total[i] > max_inflight ||
		    round_rest_idle[i] > round_rest_total[i] ||
		    round_rest_active[i] > max_inflight) {
			plateau_ok = false;
		}
	}
	settled_ok = settled_total <= warm_floor &&
	    settled_idle == settled_total && settled_active == 0;

	emit_burst_result(
	    mode,
	    (!timed_out && sysctl_error == 0 && rounds_completed == rounds &&
	    completed == rounds * requested && (!expect_reuse || reuse_ok) &&
	    plateau_ok &&
	    settled_ok) ? "ok" : "error",
	    rc, rounds, requested, started, completed, unique_threads,
	    max_inflight, main_thread_callbacks, rounds_completed,
	    round_unique_threads, round_new_threads, round_rest_total,
	    round_rest_idle, round_rest_active, round_thread_enter_delta,
	    round_reqthreads_delta, round_should_narrow_true_delta,
	    settled_total, settled_idle, settled_active, warm_floor,
	    sysctl_error,
	    timed_out, features);
	return (!timed_out && sysctl_error == 0 && rounds_completed == rounds &&
	    completed == rounds * requested && (!expect_reuse || reuse_ok) &&
	    plateau_ok &&
	    settled_ok ? 0 : 1);
}

static int
run_sustained_mode(struct dispatch_probe_state *state, uint32_t requested_default,
    uint32_t requested_high, uint32_t timeout_ms, uint32_t settle_ms,
    uint32_t sample_ms, int features)
{
	dispatch_group_t group;
	dispatch_queue_t default_queue, high_queue;
	dispatch_time_t deadline;
	pthread_t sampler_thread;
	struct dispatch_sampler sampler;
	uint32_t completed_default, completed_high, default_max_inflight;
	uint32_t main_thread_callbacks, started_default, started_high;
	uint32_t settled_total, settled_idle, settled_active, unique_threads;
	uint32_t warm_floor, warm_limit;
	int error, i, rc, wait_rc, join_error;
	bool bounded_plateau;
	bool high_ready, sampler_running, timed_out;

	memset(&sampler, 0, sizeof(sampler));
	sampler.interval_ms = sample_ms == 0 ? 100 : sample_ms;
	settled_total = 0;
	settled_idle = 0;
	settled_active = 0;
	sampler_running = false;
	warm_floor = dispatch_warm_floor();
	warm_limit = warm_floor + (requested_high != 0 ? 1U : 0U);

	group = dispatch_group_create();
	high_queue = dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0);
	default_queue = dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0);

	rc = pthread_create(&sampler_thread, NULL, dispatch_sampler_main,
	    &sampler);
	if (rc == 0)
		sampler_running = true;
	else
		sampler.sysctl_error = rc;

	for (i = 0; i < (int)requested_high; i++)
		dispatch_group_async_f(group, high_queue, state, pressure_high_worker);

	high_ready = wait_for_counter(&state->high_started, 1,
	    MIN(timeout_ms, 1000));
	if (high_ready) {
		for (i = 0; i < (int)requested_default; i++) {
			dispatch_group_async_f(group, default_queue, state,
			    pressure_default_worker);
		}
	}

	deadline = dispatch_time(DISPATCH_TIME_NOW,
	    (int64_t)timeout_ms * 1000000LL);
	wait_rc = dispatch_group_wait(group, deadline);
	timed_out = (wait_rc != 0) || !high_ready;
	rc = high_ready ? wait_rc : ETIMEDOUT;

	if (sampler_running) {
		__atomic_store_n(&sampler.stop, 1, __ATOMIC_SEQ_CST);
		join_error = pthread_join(sampler_thread, NULL);
		if (join_error != 0 && sampler.sysctl_error == 0)
			sampler.sysctl_error = join_error;
	}

	if (!timed_out && sampler.sysctl_error == 0) {
		sleep_millis(settle_ms);
		error = read_bucket_sums(&settled_total, &settled_idle,
		    &settled_active);
		if (error != 0) {
			sampler.sysctl_error = error;
			rc = error;
		}
	}

	started_high = __atomic_load_n(&state->high_started, __ATOMIC_SEQ_CST);
	completed_high = __atomic_load_n(&state->high_completed, __ATOMIC_SEQ_CST);
	started_default = __atomic_load_n(&state->default_started,
	    __ATOMIC_SEQ_CST);
	completed_default = __atomic_load_n(&state->default_completed,
	    __ATOMIC_SEQ_CST);
	default_max_inflight = __atomic_load_n(&state->default_max_inflight,
	    __ATOMIC_SEQ_CST);
	main_thread_callbacks = __atomic_load_n(&state->main_thread_callbacks,
	    __ATOMIC_SEQ_CST);
	unique_threads = unique_thread_count(state);
	bounded_plateau = sampler.peak_total <= warm_limit &&
	    settled_total <= warm_limit && settled_idle == settled_total &&
	    settled_active == 0;

	emit_sustained_result(
	    (!timed_out && sampler.sysctl_error == 0 && high_ready &&
	    completed_default == requested_default &&
	    completed_high == requested_high && bounded_plateau) ?
	    "ok" : "error",
	    rc, requested_default, requested_high, started_default,
	    completed_default, started_high, completed_high, unique_threads,
	    default_max_inflight, sampler.peak_total, sampler.peak_idle,
	    sampler.peak_active, sampler.sample_count, sampler.samples_total,
	    sampler.samples_idle, sampler.samples_active, settled_total,
	    settled_idle, settled_active, main_thread_callbacks, warm_floor,
	    high_ready, sampler.sysctl_error, timed_out, features);
	dispatch_release(group);
	return (!timed_out && sampler.sysctl_error == 0 && high_ready &&
	    completed_default == requested_default &&
	    completed_high == requested_high && bounded_plateau ? 0 : 1);
}

int
main(int argc, char **argv)
{
	const uint32_t default_sleep_ms = 20;
	const uint32_t default_high_sleep_ms = 200;
	const uint32_t default_tasks = 16;
	const uint32_t default_high_tasks = 1;
	const uint32_t default_rounds = 4;
	const uint32_t default_pause_ms = 250;
	const uint32_t default_settle_ms = 6500;
	const uint32_t default_sample_ms = 100;
	const uint32_t default_timeout_ms = 5000;
	struct dispatch_probe_state state;
	enum dispatch_probe_mode mode;
	uint32_t high_sleep_ms, pause_ms, requested, requested_high, rounds;
	uint32_t sample_ms, settle_ms, sleep_ms, timeout_ms;
	int features, i, rc;

	mode = DISPATCH_PROBE_MODE_BASIC;
	requested = default_tasks;
	requested_high = default_high_tasks;
	rounds = default_rounds;
	pause_ms = default_pause_ms;
	settle_ms = default_settle_ms;
	sample_ms = default_sample_ms;
	sleep_ms = default_sleep_ms;
	high_sleep_ms = default_high_sleep_ms;
	timeout_ms = default_timeout_ms;

	for (i = 1; i < argc; i++) {
		if (strcmp(argv[i], "--mode") == 0) {
			if (++i >= argc) {
				fprintf(stderr, "missing value for --mode\n");
				return (64);
			}
			mode = parse_mode_arg(argv[i]);
			continue;
		}
		if (strcmp(argv[i], "--tasks") == 0) {
			if (++i >= argc) {
				fprintf(stderr, "missing value for --tasks\n");
				return (64);
			}
			requested = parse_u32_arg(argv[i], "tasks");
			continue;
		}
		if (strcmp(argv[i], "--high-tasks") == 0) {
			if (++i >= argc) {
				fprintf(stderr, "missing value for --high-tasks\n");
				return (64);
			}
			requested_high = parse_u32_arg(argv[i], "high-tasks");
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
		if (strcmp(argv[i], "--pause-ms") == 0) {
			if (++i >= argc) {
				fprintf(stderr, "missing value for --pause-ms\n");
				return (64);
			}
			pause_ms = parse_u32_arg(argv[i], "pause-ms");
			continue;
		}
		if (strcmp(argv[i], "--settle-ms") == 0) {
			if (++i >= argc) {
				fprintf(stderr, "missing value for --settle-ms\n");
				return (64);
			}
			settle_ms = parse_u32_arg(argv[i], "settle-ms");
			continue;
		}
		if (strcmp(argv[i], "--sample-ms") == 0) {
			if (++i >= argc) {
				fprintf(stderr, "missing value for --sample-ms\n");
				return (64);
			}
			sample_ms = parse_u32_arg(argv[i], "sample-ms");
			continue;
		}
		if (strcmp(argv[i], "--sleep-ms") == 0) {
			if (++i >= argc) {
				fprintf(stderr, "missing value for --sleep-ms\n");
				return (64);
			}
			sleep_ms = parse_u32_arg(argv[i], "sleep-ms");
			continue;
		}
		if (strcmp(argv[i], "--high-sleep-ms") == 0) {
			if (++i >= argc) {
				fprintf(stderr,
				    "missing value for --high-sleep-ms\n");
				return (64);
			}
			high_sleep_ms = parse_u32_arg(argv[i], "high-sleep-ms");
			continue;
		}
		if (strcmp(argv[i], "--timeout-ms") == 0) {
			if (++i >= argc) {
				fprintf(stderr, "missing value for --timeout-ms\n");
				return (64);
			}
			timeout_ms = parse_u32_arg(argv[i], "timeout-ms");
			continue;
		}
		fprintf(stderr, "unknown argument: %s\n", argv[i]);
		return (64);
	}

	memset(&state, 0, sizeof(state));
	pthread_mutex_init(&state.lock, NULL);
	state.main_thread = (uintptr_t)pthread_self();
	state.sleep_ms = sleep_ms;
	state.high_sleep_ms = high_sleep_ms;

	features = _pthread_workqueue_supported();
	emit_supported_result(features);

	switch (mode) {
	case DISPATCH_PROBE_MODE_BASIC:
		rc = run_basic_mode(&state, requested, timeout_ms, features);
		break;
	case DISPATCH_PROBE_MODE_EXECUTOR:
		rc = run_executor_mode(&state, requested, timeout_ms, features);
		break;
	case DISPATCH_PROBE_MODE_AFTER:
		rc = run_after_mode(&state, requested, sleep_ms, timeout_ms,
		    features);
		break;
	case DISPATCH_PROBE_MODE_EXECUTOR_AFTER:
		rc = run_executor_after_mode(&state, requested, sleep_ms,
		    timeout_ms, features);
		break;
	case DISPATCH_PROBE_MODE_EXECUTOR_AFTER_DEFAULT_WIDTH:
		rc = run_executor_after_default_width_mode(&state, requested,
		    sleep_ms, timeout_ms, features);
		break;
	case DISPATCH_PROBE_MODE_EXECUTOR_AFTER_SYNC_WIDTH:
		rc = run_executor_after_sync_width_mode(&state, requested,
		    sleep_ms, timeout_ms, features);
		break;
	case DISPATCH_PROBE_MODE_EXECUTOR_AFTER_SETTLED:
		rc = run_executor_after_settled_mode(&state, requested, sleep_ms,
		    timeout_ms, features);
		break;
	case DISPATCH_PROBE_MODE_MAIN_EXECUTOR_AFTER_REPEAT:
		rc = run_main_executor_after_repeat_mode(&state, rounds, requested,
		    sleep_ms, features);
		break;
	case DISPATCH_PROBE_MODE_MAIN_EXECUTOR_RESUME_REPEAT:
		rc = run_main_executor_resume_repeat_mode(&state, rounds, requested,
		    sleep_ms, features);
		break;
	case DISPATCH_PROBE_MODE_WORKER_AFTER_GROUP:
		rc = run_worker_after_group_mode(&state, requested, sleep_ms,
		    timeout_ms, features);
		break;
	case DISPATCH_PROBE_MODE_MAIN:
		rc = run_main_mode(&state, requested, features);
		break;
	case DISPATCH_PROBE_MODE_MAIN_AFTER:
		rc = run_main_after_mode(&state, requested, sleep_ms, features);
		break;
	case DISPATCH_PROBE_MODE_MAIN_ROUNDTRIP_AFTER:
		rc = run_main_roundtrip_after_mode(&state, requested, sleep_ms,
		    features);
		break;
	case DISPATCH_PROBE_MODE_MAIN_GROUP_AFTER:
		rc = run_main_group_after_mode(&state, requested, sleep_ms,
		    features);
		break;
	case DISPATCH_PROBE_MODE_PRESSURE:
		rc = run_pressure_mode(&state, requested, requested_high,
		    timeout_ms, features);
		break;
	case DISPATCH_PROBE_MODE_BURST_REUSE:
		rc = run_burst_mode("burst-reuse", &state, requested, rounds,
		    pause_ms, settle_ms, timeout_ms, true, features);
		break;
	case DISPATCH_PROBE_MODE_TIMEOUT_GAP:
		rc = run_burst_mode("timeout-gap", &state, requested, rounds,
		    pause_ms, settle_ms, timeout_ms, false, features);
		break;
	case DISPATCH_PROBE_MODE_SUSTAINED:
		rc = run_sustained_mode(&state, requested, requested_high,
		    timeout_ms, settle_ms, sample_ms, features);
		break;
	default:
		rc = 64;
		break;
	}

	pthread_mutex_destroy(&state.lock);
	return (rc);
}
