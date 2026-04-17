#include "twq_pressure_provider_preview.h"

#include <sys/sysctl.h>

#include <errno.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

uint64_t
twq_pressure_provider_monotonic_time_ns(void)
{
	struct timespec ts;

	if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0)
		return (0);
	return ((uint64_t)ts.tv_sec * 1000000000ULL + (uint64_t)ts.tv_nsec);
}

uint64_t
twq_pressure_provider_sum_values(const uint64_t *values, size_t count)
{
	uint64_t sum;
	size_t i;

	sum = 0;
	for (i = 0; i < count; i++)
		sum += values[i];
	return (sum);
}

uint64_t
twq_pressure_provider_delta_or_zero_u64(uint64_t current, uint64_t base)
{
	if (current < base)
		return (0);
	return (current - base);
}

uint64_t
twq_pressure_provider_nonidle_workers_u64(uint64_t total, uint64_t idle)
{
	if (total < idle)
		return (0);
	return (total - idle);
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
read_sysctl_u64(const char *name, uint64_t *value_out)
{
	size_t len;

	len = sizeof(*value_out);
	if (sysctlbyname(name, value_out, &len, NULL, 0) != 0)
		return (errno);
	return (0);
}

static int
parse_u64_array(const char *text, uint64_t *values, size_t *count_out)
{
	char buf[512];
	char *cursor, *end;
	unsigned long long parsed;
	size_t count;

	if (strlen(text) >= sizeof(buf))
		return (ENAMETOOLONG);

	memcpy(buf, text, strlen(text) + 1);
	cursor = buf;
	count = 0;

	while (*cursor != '\0') {
		if (count >= TWQ_PRESSURE_PROVIDER_MAX_BUCKETS)
			return (E2BIG);
		parsed = strtoull(cursor, &end, 10);
		if (end == cursor)
			return (EPROTO);
		values[count++] = (uint64_t)parsed;
		if (*end == '\0')
			break;
		if (*end != ',')
			return (EPROTO);
		cursor = end + 1;
	}

	*count_out = count;
	return (0);
}

static int
read_sysctl_u64_array(const char *name, uint64_t *values, size_t *count_out)
{
	char buf[512];
	int error;

	error = read_sysctl_text(name, buf, sizeof(buf));
	if (error != 0)
		return (error);
	return (parse_u64_array(buf, values, count_out));
}

static int
read_bucket_array(const char *name, uint64_t *values, size_t *bucket_count)
{
	size_t count;
	int error;

	error = read_sysctl_u64_array(name, values, &count);
	if (error != 0)
		return (error);

	if (*bucket_count == 0) {
		*bucket_count = count;
		return (0);
	}
	if (*bucket_count != count)
		return (EPROTO);
	return (0);
}

int
twq_pressure_provider_read_snapshot_v1(struct twq_pressure_provider_snapshot_v1 *snapshot)
{
	size_t bucket_count;
	int error;
	size_t i;

	if (snapshot == NULL)
		return (EINVAL);

	memset(snapshot, 0, sizeof(*snapshot));
	bucket_count = 0;

	error = read_sysctl_u64("kern.twq.reqthreads_count",
	    &snapshot->reqthreads_count);
	if (error != 0)
		return (error);
	error = read_sysctl_u64("kern.twq.thread_enter_count",
	    &snapshot->thread_enter_count);
	if (error != 0)
		return (error);
	error = read_sysctl_u64("kern.twq.thread_return_count",
	    &snapshot->thread_return_count);
	if (error != 0)
		return (error);
	error = read_sysctl_u64("kern.twq.switch_block_count",
	    &snapshot->switch_block_count);
	if (error != 0)
		return (error);
	error = read_sysctl_u64("kern.twq.switch_unblock_count",
	    &snapshot->switch_unblock_count);
	if (error != 0)
		return (error);
	error = read_sysctl_u64("kern.twq.should_narrow_true_count",
	    &snapshot->should_narrow_true_count);
	if (error != 0)
		return (error);
	error = read_bucket_array("kern.twq.bucket_req_total",
	    snapshot->bucket_req_total, &bucket_count);
	if (error != 0)
		return (error);
	error = read_bucket_array("kern.twq.bucket_admit_total",
	    snapshot->bucket_admit_total, &bucket_count);
	if (error != 0)
		return (error);
	error = read_bucket_array("kern.twq.bucket_switch_block_total",
	    snapshot->bucket_switch_block_total, &bucket_count);
	if (error != 0)
		return (error);
	error = read_bucket_array("kern.twq.bucket_switch_unblock_total",
	    snapshot->bucket_switch_unblock_total, &bucket_count);
	if (error != 0)
		return (error);
	error = read_bucket_array("kern.twq.bucket_total_current",
	    snapshot->bucket_total_current, &bucket_count);
	if (error != 0)
		return (error);
	error = read_bucket_array("kern.twq.bucket_idle_current",
	    snapshot->bucket_idle_current, &bucket_count);
	if (error != 0)
		return (error);
	error = read_bucket_array("kern.twq.bucket_active_current",
	    snapshot->bucket_active_current, &bucket_count);
	if (error != 0)
		return (error);

	snapshot->struct_size = sizeof(*snapshot);
	snapshot->version = TWQ_PRESSURE_PROVIDER_PREVIEW_VERSION;
	snapshot->bucket_count = (uint32_t)bucket_count;
	snapshot->monotonic_time_ns = twq_pressure_provider_monotonic_time_ns();
	snapshot->requested_workers_total = twq_pressure_provider_sum_values(
	    snapshot->bucket_req_total, bucket_count);
	snapshot->admitted_workers_total = twq_pressure_provider_sum_values(
	    snapshot->bucket_admit_total, bucket_count);
	snapshot->blocked_workers_total = twq_pressure_provider_sum_values(
	    snapshot->bucket_switch_block_total, bucket_count);
	snapshot->unblocked_workers_total = twq_pressure_provider_sum_values(
	    snapshot->bucket_switch_unblock_total, bucket_count);
	snapshot->total_workers_current = twq_pressure_provider_sum_values(
	    snapshot->bucket_total_current, bucket_count);
	snapshot->idle_workers_current = twq_pressure_provider_sum_values(
	    snapshot->bucket_idle_current, bucket_count);
	snapshot->active_workers_current = twq_pressure_provider_sum_values(
	    snapshot->bucket_active_current, bucket_count);
	snapshot->nonidle_workers_current =
	    twq_pressure_provider_nonidle_workers_u64(
		snapshot->total_workers_current, snapshot->idle_workers_current);

	for (i = 0; i < bucket_count; i++) {
		snapshot->bucket_nonidle_current[i] =
		    twq_pressure_provider_nonidle_workers_u64(
			snapshot->bucket_total_current[i],
			snapshot->bucket_idle_current[i]);
	}

	return (0);
}
