#include <pthread/workqueue_private.h>

#include <sys/sysctl.h>
#include <sys/thr.h>

#include <errno.h>
#include <inttypes.h>
#include <math.h>
#include <pthread.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

enum bench_mode {
	MODE_WAKE_DEFAULT = 0,
	MODE_WAKE_OVERCOMMIT
};

struct counter_snapshot {
	uint64_t init_count;
	uint64_t reqthreads_count;
	uint64_t thread_enter_count;
	uint64_t thread_return_count;
	uint64_t thread_transfer_count;
};

struct counter_delta {
	uint64_t init_count;
	uint64_t reqthreads_count;
	uint64_t thread_enter_count;
	uint64_t thread_return_count;
	uint64_t thread_transfer_count;
};

struct stats {
	uint64_t mean_ns;
	uint64_t median_ns;
	uint64_t p95_ns;
	uint64_t p99_ns;
	uint64_t min_ns;
	uint64_t max_ns;
	uint64_t stddev_ns;
};

struct bench_state {
	pthread_mutex_t lock;
	pthread_cond_t cv;
	uint32_t callback_seq;
	uint64_t callback_start_ns;
	uint64_t callback_tid;
	uint64_t callback_priority;
};

static struct bench_state g_state = {
	.lock = PTHREAD_MUTEX_INITIALIZER,
	.cv = PTHREAD_COND_INITIALIZER,
};

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

static enum bench_mode
parse_mode(const char *value)
{

	if (strcmp(value, "wake-default") == 0)
		return (MODE_WAKE_DEFAULT);
	if (strcmp(value, "wake-overcommit") == 0)
		return (MODE_WAKE_OVERCOMMIT);
	fprintf(stderr, "invalid mode: %s\n", value);
	exit(64);
}

static const char *
mode_name(enum bench_mode mode)
{

	switch (mode) {
	case MODE_WAKE_DEFAULT:
		return ("wake-default");
	case MODE_WAKE_OVERCOMMIT:
		return ("wake-overcommit");
	}
	return ("unknown");
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

static uint64_t
timespec_to_ns(const struct timespec *ts)
{

	return ((uint64_t)ts->tv_sec * 1000000000ULL + (uint64_t)ts->tv_nsec);
}

static uint64_t
now_monotonic_ns(void)
{
	struct timespec ts;

	if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0) {
		perror("clock_gettime(CLOCK_MONOTONIC)");
		exit(70);
	}
	return (timespec_to_ns(&ts));
}

static int
read_sysctl_u64(const char *name, uint64_t *value_out)
{
	size_t len;

	len = sizeof(*value_out);
	if (sysctlbyname(name, value_out, &len, NULL, 0) != 0)
		return (errno);
	return (0);
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
wait_for_quiescent_total(uint32_t expected_total, uint32_t timeout_ms,
    uint32_t *total_out, uint32_t *idle_out, uint32_t *active_out)
{
	uint32_t waited;
	int error;

	for (waited = 0; waited <= timeout_ms; waited += 10) {
		error = read_bucket_sums(total_out, idle_out, active_out);
		if (error != 0)
			return (error);
		if (*total_out == expected_total && *idle_out == expected_total &&
		    *active_out == 0)
			return (0);
		sleep_millis(10);
	}
	return (ETIMEDOUT);
}

static int
read_kernel_string(const char *name, char *buf, size_t buf_size)
{
	int error;

	error = read_sysctl_text(name, buf, buf_size);
	if (error != 0) {
		buf[0] = '\0';
		return (error);
	}
	return (0);
}

static struct counter_snapshot
read_counter_snapshot(void)
{
	struct counter_snapshot snapshot;
	int error;

	memset(&snapshot, 0, sizeof(snapshot));
	error = read_sysctl_u64("kern.twq.init_count", &snapshot.init_count);
	if (error != 0)
		goto fail;
	error = read_sysctl_u64("kern.twq.reqthreads_count",
	    &snapshot.reqthreads_count);
	if (error != 0)
		goto fail;
	error = read_sysctl_u64("kern.twq.thread_enter_count",
	    &snapshot.thread_enter_count);
	if (error != 0)
		goto fail;
	error = read_sysctl_u64("kern.twq.thread_return_count",
	    &snapshot.thread_return_count);
	if (error != 0)
		goto fail;
	error = read_sysctl_u64("kern.twq.thread_transfer_count",
	    &snapshot.thread_transfer_count);
	if (error != 0)
		goto fail;
	return (snapshot);

fail:
	fprintf(stderr, "failed to read TWQ counters: %s\n", strerror(error));
	exit(70);
}

static struct counter_delta
delta_counters(struct counter_snapshot before, struct counter_snapshot after)
{
	struct counter_delta delta;

	delta.init_count = after.init_count - before.init_count;
	delta.reqthreads_count = after.reqthreads_count - before.reqthreads_count;
	delta.thread_enter_count =
	    after.thread_enter_count - before.thread_enter_count;
	delta.thread_return_count =
	    after.thread_return_count - before.thread_return_count;
	delta.thread_transfer_count =
	    after.thread_transfer_count - before.thread_transfer_count;
	return (delta);
}

static void
worker_cb(pthread_priority_t priority)
{
	struct timespec ts;
	long tid;

	clock_gettime(CLOCK_MONOTONIC, &ts);
	tid = 0;
	(void)thr_self(&tid);

	pthread_mutex_lock(&g_state.lock);
	g_state.callback_seq++;
	g_state.callback_start_ns = timespec_to_ns(&ts);
	g_state.callback_tid = (uint64_t)tid;
	g_state.callback_priority = (uint64_t)priority;
	pthread_cond_broadcast(&g_state.cv);
	pthread_mutex_unlock(&g_state.lock);
}

static int
wait_for_callback_seq(uint32_t expected_seq, uint32_t timeout_ms,
    uint64_t *callback_start_ns_out, uint64_t *callback_tid_out,
    uint64_t *callback_priority_out)
{
	struct timespec abstime;
	int error;

	if (clock_gettime(CLOCK_REALTIME, &abstime) != 0)
		return (errno);
	abstime.tv_sec += timeout_ms / 1000U;
	abstime.tv_nsec += (long)(timeout_ms % 1000U) * 1000000L;
	if (abstime.tv_nsec >= 1000000000L) {
		abstime.tv_sec++;
		abstime.tv_nsec -= 1000000000L;
	}

	pthread_mutex_lock(&g_state.lock);
	error = 0;
	while (g_state.callback_seq < expected_seq) {
		error = pthread_cond_timedwait(&g_state.cv, &g_state.lock, &abstime);
		if (error != 0)
			break;
	}
	if (error == 0 && g_state.callback_seq >= expected_seq) {
		*callback_start_ns_out = g_state.callback_start_ns;
		*callback_tid_out = g_state.callback_tid;
		*callback_priority_out = g_state.callback_priority;
	}
	pthread_mutex_unlock(&g_state.lock);
	return (error);
}

static int
issue_addthreads(enum bench_mode mode)
{
	int options;

	options = (mode == MODE_WAKE_OVERCOMMIT) ?
	    WORKQ_ADDTHREADS_OPTION_OVERCOMMIT : 0;
	return (pthread_workqueue_addthreads_np(WORKQ_DEFAULT_PRIOQUEUE, options,
	    1));
}

static int
run_request(enum bench_mode mode, uint32_t callback_timeout_ms,
    uint64_t *latency_ns_out, uint64_t *callback_tid_out,
    uint64_t *callback_priority_out)
{
	uint64_t callback_start_ns, callback_tid, callback_priority, start_ns;
	uint32_t expected_seq;
	int error;

	pthread_mutex_lock(&g_state.lock);
	expected_seq = g_state.callback_seq + 1;
	pthread_mutex_unlock(&g_state.lock);

	start_ns = now_monotonic_ns();
	error = issue_addthreads(mode);
	if (error != 0)
		return (error);

	error = wait_for_callback_seq(expected_seq, callback_timeout_ms,
	    &callback_start_ns, &callback_tid, &callback_priority);
	if (error != 0)
		return (error);

	if (callback_start_ns >= start_ns)
		*latency_ns_out = callback_start_ns - start_ns;
	else
		*latency_ns_out = 0;
	*callback_tid_out = callback_tid;
	*callback_priority_out = callback_priority;
	return (0);
}

static int
cmp_u64(const void *lhs, const void *rhs)
{
	const uint64_t *a, *b;

	a = lhs;
	b = rhs;
	if (*a < *b)
		return (-1);
	if (*a > *b)
		return (1);
	return (0);
}

static uint64_t
percentile(const uint64_t *sorted, size_t len, uint32_t pct)
{
	size_t rank;

	if (len == 0)
		return (0);
	if (len == 1)
		return (sorted[0]);
	rank = (size_t)(((len - 1) * (uint64_t)pct) / 100ULL);
	return (sorted[rank]);
}

static struct stats
compute_stats(const uint64_t *samples, size_t count)
{
	struct stats stats;
	double delta, mean, variance, variance_sum;
	uint64_t *sorted;
	uint64_t sum;
	size_t i;

	memset(&stats, 0, sizeof(stats));
	if (count == 0)
		return (stats);

	sorted = calloc(count, sizeof(*sorted));
	if (sorted == NULL) {
		perror("calloc");
		exit(71);
	}
	memcpy(sorted, samples, count * sizeof(*sorted));
	qsort(sorted, count, sizeof(*sorted), cmp_u64);

	sum = 0;
	for (i = 0; i < count; i++)
		sum += samples[i];
	mean = (double)sum / (double)count;

	variance_sum = 0.0;
	for (i = 0; i < count; i++) {
		delta = (double)samples[i] - mean;
		variance_sum += delta * delta;
	}
	variance = variance_sum / (double)count;

	stats.mean_ns = (uint64_t)llround(mean);
	stats.median_ns = percentile(sorted, count, 50);
	stats.p95_ns = percentile(sorted, count, 95);
	stats.p99_ns = percentile(sorted, count, 99);
	stats.min_ns = sorted[0];
	stats.max_ns = sorted[count - 1];
	stats.stddev_ns = (uint64_t)llround(sqrt(variance));

	free(sorted);
	return (stats);
}

static void
emit_json_escaped(const char *text)
{
	const unsigned char *p;

	putchar('"');
	for (p = (const unsigned char *)text; *p != '\0'; p++) {
		switch (*p) {
		case '\\':
			fputs("\\\\", stdout);
			break;
		case '"':
			fputs("\\\"", stdout);
			break;
		case '\n':
			fputs("\\n", stdout);
			break;
		case '\r':
			fputs("\\r", stdout);
			break;
		case '\t':
			fputs("\\t", stdout);
			break;
		default:
			putchar(*p);
			break;
		}
	}
	putchar('"');
}

int
main(int argc, char **argv)
{
	char kernel_bootfile[256];
	char kernel_ident[128];
	char kernel_osrelease[128];
	enum bench_mode mode;
	struct counter_delta delta;
	struct counter_snapshot after, before;
	struct stats stats;
	uint64_t callback_priority, callback_tid, last_callback_priority;
	uint64_t last_callback_tid, prime_callback_ns, prime_callback_priority;
	uint64_t prime_callback_tid, sample_latency;
	uint64_t thread_mismatch_count;
	uint64_t *samples;
	uint32_t active, callback_timeout_ms, idle, last_error, prime_timeout_ms;
	uint32_t quiescent_timeout_ms, sample_errors, samples_count, settle_ms;
	uint32_t timeout_error, total, total_after, total_before, warmup;
	int init_rc, rc;
	size_t i;

	mode = MODE_WAKE_DEFAULT;
	samples_count = 256;
	warmup = 32;
	settle_ms = 50;
	prime_timeout_ms = 3000;
	callback_timeout_ms = 3000;
	quiescent_timeout_ms = 3000;

	for (i = 1; i < (size_t)argc; i++) {
		if (strcmp(argv[i], "--mode") == 0) {
			if (++i >= (size_t)argc) {
				fprintf(stderr, "missing value for --mode\n");
				return (64);
			}
			mode = parse_mode(argv[i]);
			continue;
		}
		if (strcmp(argv[i], "--samples") == 0) {
			if (++i >= (size_t)argc) {
				fprintf(stderr, "missing value for --samples\n");
				return (64);
			}
			samples_count = parse_u32_arg(argv[i], "samples");
			continue;
		}
		if (strcmp(argv[i], "--warmup") == 0) {
			if (++i >= (size_t)argc) {
				fprintf(stderr, "missing value for --warmup\n");
				return (64);
			}
			warmup = parse_u32_arg(argv[i], "warmup");
			continue;
		}
		if (strcmp(argv[i], "--settle-ms") == 0) {
			if (++i >= (size_t)argc) {
				fprintf(stderr, "missing value for --settle-ms\n");
				return (64);
			}
			settle_ms = parse_u32_arg(argv[i], "settle-ms");
			continue;
		}
		if (strcmp(argv[i], "--prime-timeout-ms") == 0) {
			if (++i >= (size_t)argc) {
				fprintf(stderr, "missing value for --prime-timeout-ms\n");
				return (64);
			}
			prime_timeout_ms = parse_u32_arg(argv[i], "prime-timeout-ms");
			continue;
		}
		if (strcmp(argv[i], "--callback-timeout-ms") == 0) {
			if (++i >= (size_t)argc) {
				fprintf(stderr, "missing value for --callback-timeout-ms\n");
				return (64);
			}
			callback_timeout_ms = parse_u32_arg(argv[i],
			    "callback-timeout-ms");
			continue;
		}
		if (strcmp(argv[i], "--quiescent-timeout-ms") == 0) {
			if (++i >= (size_t)argc) {
				fprintf(stderr,
				    "missing value for --quiescent-timeout-ms\n");
				return (64);
			}
			quiescent_timeout_ms = parse_u32_arg(argv[i],
			    "quiescent-timeout-ms");
			continue;
		}
		fprintf(stderr, "unknown argument: %s\n", argv[i]);
		return (64);
	}

	if (samples_count == 0) {
		fprintf(stderr, "samples must be greater than zero\n");
		return (64);
	}

	read_kernel_string("kern.ident", kernel_ident, sizeof(kernel_ident));
	read_kernel_string("kern.osrelease", kernel_osrelease,
	    sizeof(kernel_osrelease));
	read_kernel_string("kern.bootfile", kernel_bootfile,
	    sizeof(kernel_bootfile));

	init_rc = _pthread_workqueue_init(worker_cb, 16, 0);
	if (init_rc != 0) {
		fprintf(stderr, "_pthread_workqueue_init failed: %d\n", init_rc);
		return (1);
	}

	prime_callback_ns = 0;
	prime_callback_tid = 0;
	prime_callback_priority = 0;
	rc = run_request(mode, prime_timeout_ms, &prime_callback_ns,
	    &prime_callback_tid, &prime_callback_priority);
	if (rc != 0) {
		fprintf(stderr, "prime request failed: %d\n", rc);
		return (1);
	}

	total = idle = active = 0;
	timeout_error = wait_for_quiescent_total(1, quiescent_timeout_ms,
	    &total, &idle, &active);
	if (timeout_error != 0) {
		fprintf(stderr, "prime quiescent wait failed: %d\n",
		    timeout_error);
		return (1);
	}

	for (i = 0; i < warmup; i++) {
		rc = run_request(mode, callback_timeout_ms, &sample_latency,
		    &callback_tid, &callback_priority);
		if (rc != 0) {
			fprintf(stderr, "warmup request failed: %d\n", rc);
			return (1);
		}
		timeout_error = wait_for_quiescent_total(1, quiescent_timeout_ms,
		    &total, &idle, &active);
		if (timeout_error != 0) {
			fprintf(stderr, "warmup quiescent wait failed: %d\n",
			    timeout_error);
			return (1);
		}
	}

	sleep_millis(settle_ms);
	before = read_counter_snapshot();
	total_before = idle = active = 0;
	timeout_error = read_bucket_sums(&total_before, &idle, &active);
	if (timeout_error != 0) {
		fprintf(stderr, "failed to read bucket sums before samples: %d\n",
		    timeout_error);
		return (1);
	}

	samples = calloc(samples_count, sizeof(*samples));
	if (samples == NULL) {
		perror("calloc");
		return (71);
	}

	sample_errors = 0;
	last_error = 0;
	thread_mismatch_count = 0;
	last_callback_tid = prime_callback_tid;
	last_callback_priority = prime_callback_priority;
	for (i = 0; i < samples_count; i++) {
		rc = run_request(mode, callback_timeout_ms, &samples[i],
		    &callback_tid, &callback_priority);
		if (rc != 0) {
			samples[i] = 0;
			sample_errors++;
			last_error = (uint32_t)rc;
			continue;
		}
		if (callback_tid != prime_callback_tid)
			thread_mismatch_count++;
		last_callback_tid = callback_tid;
		last_callback_priority = callback_priority;
		timeout_error = wait_for_quiescent_total(1, quiescent_timeout_ms,
		    &total, &idle, &active);
		if (timeout_error != 0) {
			sample_errors++;
			last_error = (uint32_t)timeout_error;
			break;
		}
	}

	sleep_millis(settle_ms);
	after = read_counter_snapshot();
	total_after = idle = active = 0;
	timeout_error = read_bucket_sums(&total_after, &idle, &active);
	if (timeout_error != 0) {
		fprintf(stderr, "failed to read bucket sums after samples: %d\n",
		    timeout_error);
		free(samples);
		return (1);
	}

	stats = compute_stats(samples, samples_count);
	delta = delta_counters(before, after);

	printf("{\"kind\":\"workqueue-bench\",\"status\":");
	emit_json_escaped(sample_errors == 0 ? "ok" : "error");
	printf(",\"data\":{");
	printf("\"benchmark\":\"workqueue-wake\",");
	printf("\"mode\":\"%s\",", mode_name(mode));
	printf("\"samples\":%u,", samples_count);
	printf("\"warmup\":%u,", warmup);
	printf("\"settle_ms\":%u,", settle_ms);
	printf("\"prime_timeout_ms\":%u,", prime_timeout_ms);
	printf("\"callback_timeout_ms\":%u,", callback_timeout_ms);
	printf("\"quiescent_timeout_ms\":%u,", quiescent_timeout_ms);
	printf("\"mean_ns\":%" PRIu64 ",", stats.mean_ns);
	printf("\"median_ns\":%" PRIu64 ",", stats.median_ns);
	printf("\"p95_ns\":%" PRIu64 ",", stats.p95_ns);
	printf("\"p99_ns\":%" PRIu64 ",", stats.p99_ns);
	printf("\"min_ns\":%" PRIu64 ",", stats.min_ns);
	printf("\"max_ns\":%" PRIu64 ",", stats.max_ns);
	printf("\"stddev_ns\":%" PRIu64 ",", stats.stddev_ns);
	printf("\"prime_callback_ns\":%" PRIu64 ",", prime_callback_ns);
	printf("\"prime_thread_tid\":%" PRIu64 ",", prime_callback_tid);
	printf("\"last_thread_tid\":%" PRIu64 ",", last_callback_tid);
	printf("\"last_priority\":%" PRIu64 ",", last_callback_priority);
	printf("\"thread_mismatch_count\":%" PRIu64 ",", thread_mismatch_count);
	printf("\"sample_errors\":%u,", sample_errors);
	printf("\"last_error\":%u,", last_error);
	printf("\"before_total\":%u,", total_before);
	printf("\"after_total\":%u,", total_after);
	printf("\"counter_delta\":{");
	printf("\"init_count\":%" PRIu64 ",", delta.init_count);
	printf("\"reqthreads_count\":%" PRIu64 ",", delta.reqthreads_count);
	printf("\"thread_enter_count\":%" PRIu64 ",",
	    delta.thread_enter_count);
	printf("\"thread_return_count\":%" PRIu64 ",",
	    delta.thread_return_count);
	printf("\"thread_transfer_count\":%" PRIu64 "}",
	    delta.thread_transfer_count);
	printf("},\"meta\":{");
	printf("\"component\":\"c\",");
	printf("\"binary\":\"twq-bench-workqueue-wake\",");
	printf("\"kernel_ident\":");
	emit_json_escaped(kernel_ident);
	printf(",\"kernel_osrelease\":");
	emit_json_escaped(kernel_osrelease);
	printf(",\"kernel_bootfile\":");
	emit_json_escaped(kernel_bootfile);
	printf("}}\n");

	free(samples);
	return (sample_errors == 0 ? 0 : 1);
}
