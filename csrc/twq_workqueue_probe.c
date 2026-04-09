#include <pthread/workqueue_private.h>

#include <sys/sysctl.h>
#include <errno.h>
#include <inttypes.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

static volatile uint32_t callback_count;
static volatile uint64_t last_priority;
static volatile uint32_t narrow_true_count;
static volatile uint32_t narrow_false_count;

static void
emit_result(const char *mode, const char *status, int rc, uint32_t requested,
    uint32_t observed, bool timed_out, int features, uint64_t priority,
    uint32_t narrow_true, uint32_t narrow_false)
{

	printf("{\"kind\":\"zig-workq-probe\",\"status\":\"%s\",\"data\":{"
	    "\"mode\":\"%s\",\"rc\":%d,\"requested\":%u,\"observed\":%u,"
	    "\"timed_out\":%s,\"features\":%d,\"priority\":%" PRIu64 ","
	    "\"narrow_true\":%u,\"narrow_false\":%u},\"meta\":{"
	    "\"component\":\"c\",\"binary\":\"twq-workqueue-probe\"}}\n",
	    status, mode, rc, requested, observed, timed_out ? "true" : "false",
	    features, priority, narrow_true, narrow_false);
	fflush(stdout);
}

static void
emit_idle_timeout_result(const char *status, int rc, uint32_t requested,
    uint32_t observed, uint32_t before_total, uint32_t before_idle,
    uint32_t before_active, uint32_t settled_total, uint32_t settled_idle,
    uint32_t settled_active, uint32_t idle_wait_ms, bool overcommit,
    uint32_t warm_floor, int sysctl_error, int features)
{

	printf("{\"kind\":\"zig-workq-probe\",\"status\":\"%s\",\"data\":{"
	    "\"mode\":\"idle-timeout\",\"rc\":%d,\"requested\":%u,"
	    "\"observed\":%u,\"before_total\":%u,\"before_idle\":%u,"
	    "\"before_active\":%u,\"settled_total\":%u,\"settled_idle\":%u,"
	    "\"settled_active\":%u,\"idle_wait_ms\":%u,\"overcommit\":%s,"
	    "\"warm_floor\":%u,\"sysctl_error\":%d,\"features\":%d},"
	    "\"meta\":{\"component\":\"c\",\"binary\":\"twq-workqueue-probe\"}}\n",
	    status, rc, requested, observed, before_total, before_idle,
	    before_active, settled_total, settled_idle, settled_active,
	    idle_wait_ms, overcommit ? "true" : "false", warm_floor,
	    sysctl_error, features);
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

static uint32_t
workqueue_warm_floor(void)
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
wait_for_quiescent_buckets(uint32_t expected_total, uint32_t timeout_ms,
    uint32_t *total_out, uint32_t *idle_out, uint32_t *active_out)
{
	uint32_t waited;
	int error;

	for (waited = 0; waited <= timeout_ms; waited += 10) {
		error = read_bucket_sums(total_out, idle_out, active_out);
		if (error != 0)
			return (error);
		if (*total_out >= expected_total && *active_out == 0 &&
		    *idle_out == *total_out) {
			return (0);
		}
		sleep_millis(10);
	}

	return (ETIMEDOUT);
}

static void
worker_cb(pthread_priority_t priority)
{

	__atomic_add_fetch(&callback_count, 1, __ATOMIC_SEQ_CST);
	__atomic_store_n(&last_priority, priority, __ATOMIC_SEQ_CST);
	if (_pthread_workqueue_should_narrow(priority))
		__atomic_add_fetch(&narrow_true_count, 1, __ATOMIC_SEQ_CST);
	else
		__atomic_add_fetch(&narrow_false_count, 1, __ATOMIC_SEQ_CST);
	usleep(10000);
}

int
main(int argc, char **argv)
{
	const uint32_t default_timeout_ms = 3000;
	uint32_t before_active, before_idle, before_total, idle_wait_ms;
	uint32_t narrow_false, narrow_true, numthreads, observed;
	uint32_t settled_active, settled_idle, settled_total, timeout_ms;
	uint32_t warm_floor;
	uint64_t priority;
	int add_rc, features, init_rc, options, rc, sysctl_error;
	bool overcommit, timed_out;
	int i;

	numthreads = 2;
	timeout_ms = default_timeout_ms;
	idle_wait_ms = 0;
	overcommit = false;

	for (i = 1; i < argc; i++) {
		if (strcmp(argv[i], "--numthreads") == 0) {
			if (++i >= argc) {
				fprintf(stderr, "missing value for --numthreads\n");
				return (64);
			}
			numthreads = parse_u32_arg(argv[i], "numthreads");
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
		if (strcmp(argv[i], "--idle-wait-ms") == 0) {
			if (++i >= argc) {
				fprintf(stderr, "missing value for --idle-wait-ms\n");
				return (64);
			}
			idle_wait_ms = parse_u32_arg(argv[i], "idle-wait-ms");
			continue;
		}
		if (strcmp(argv[i], "--overcommit") == 0) {
			overcommit = true;
			continue;
		}
		fprintf(stderr, "unknown argument: %s\n", argv[i]);
		return (64);
	}

	warm_floor = workqueue_warm_floor();
	options = overcommit ? WORKQ_ADDTHREADS_OPTION_OVERCOMMIT : 0;
	features = _pthread_workqueue_supported();
	emit_result("supported", "ok", features, 0, 0, false, features, 0, 0, 0);

	init_rc = _pthread_workqueue_init(worker_cb, 16, 0);
	emit_result("init", init_rc == 0 ? "ok" : "error", init_rc, 0, 0, false,
	    features, 0, 0, 0);
	if (init_rc != 0)
		return (1);

	add_rc = pthread_workqueue_addthreads_np(WORKQ_DEFAULT_PRIOQUEUE, options,
	    (int)numthreads);
	emit_result("addthreads", add_rc == 0 ? "ok" : "error", add_rc, numthreads,
	    0, false, features, 0, 0, 0);
	if (add_rc != 0)
		return (1);

	timed_out = true;
	for (i = 0; i < (int)(timeout_ms / 10); i++) {
		if (__atomic_load_n(&callback_count, __ATOMIC_SEQ_CST) >= numthreads) {
			timed_out = false;
			break;
		}
		usleep(10000);
	}

	observed = __atomic_load_n(&callback_count, __ATOMIC_SEQ_CST);
	priority = __atomic_load_n(&last_priority, __ATOMIC_SEQ_CST);
	narrow_true = __atomic_load_n(&narrow_true_count, __ATOMIC_SEQ_CST);
	narrow_false = __atomic_load_n(&narrow_false_count, __ATOMIC_SEQ_CST);

	emit_result("callbacks",
	    (!timed_out && observed >= numthreads) ? "ok" : "error", 0,
	    numthreads, observed, timed_out, features, priority, narrow_true,
	    narrow_false);
	if (timed_out || observed < numthreads)
		return (1);

	if (idle_wait_ms == 0)
		return (0);

	before_total = 0;
	before_idle = 0;
	before_active = 0;
	settled_total = 0;
	settled_idle = 0;
	settled_active = 0;
	sysctl_error = wait_for_quiescent_buckets(numthreads, timeout_ms,
	    &before_total, &before_idle, &before_active);
	if (sysctl_error == 0) {
		sleep_millis(idle_wait_ms);
		sysctl_error = read_bucket_sums(&settled_total, &settled_idle,
		    &settled_active);
	}

	rc = 0;
	if (sysctl_error != 0)
		rc = sysctl_error;
	emit_idle_timeout_result(
	    (sysctl_error == 0 && before_total > warm_floor &&
	    settled_total == warm_floor && settled_idle == warm_floor &&
	    settled_active == 0) ? "ok" : "error",
	    rc, numthreads, observed, before_total, before_idle, before_active,
	    settled_total, settled_idle, settled_active, idle_wait_ms,
	    overcommit, warm_floor, sysctl_error, features);

	if (sysctl_error != 0 || before_total <= warm_floor ||
	    settled_total != warm_floor || settled_idle != warm_floor ||
	    settled_active != 0)
		return (1);

	return (0);
}
