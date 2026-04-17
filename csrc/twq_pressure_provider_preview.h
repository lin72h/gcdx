#ifndef TWQ_PRESSURE_PROVIDER_PREVIEW_H
#define TWQ_PRESSURE_PROVIDER_PREVIEW_H

#include <stddef.h>
#include <stdint.h>

#define TWQ_PRESSURE_PROVIDER_PREVIEW_VERSION 1U
#define TWQ_PRESSURE_PROVIDER_MAX_BUCKETS 16U

struct twq_pressure_provider_snapshot_v1 {
	size_t struct_size;
	uint32_t version;
	uint32_t bucket_count;
	uint64_t monotonic_time_ns;
	uint64_t reqthreads_count;
	uint64_t thread_enter_count;
	uint64_t thread_return_count;
	uint64_t switch_block_count;
	uint64_t switch_unblock_count;
	uint64_t should_narrow_true_count;
	uint64_t requested_workers_total;
	uint64_t admitted_workers_total;
	uint64_t blocked_workers_total;
	uint64_t unblocked_workers_total;
	uint64_t total_workers_current;
	uint64_t idle_workers_current;
	uint64_t nonidle_workers_current;
	uint64_t active_workers_current;
	uint64_t bucket_req_total[TWQ_PRESSURE_PROVIDER_MAX_BUCKETS];
	uint64_t bucket_admit_total[TWQ_PRESSURE_PROVIDER_MAX_BUCKETS];
	uint64_t bucket_switch_block_total[TWQ_PRESSURE_PROVIDER_MAX_BUCKETS];
	uint64_t bucket_switch_unblock_total[TWQ_PRESSURE_PROVIDER_MAX_BUCKETS];
	uint64_t bucket_total_current[TWQ_PRESSURE_PROVIDER_MAX_BUCKETS];
	uint64_t bucket_idle_current[TWQ_PRESSURE_PROVIDER_MAX_BUCKETS];
	uint64_t bucket_nonidle_current[TWQ_PRESSURE_PROVIDER_MAX_BUCKETS];
	uint64_t bucket_active_current[TWQ_PRESSURE_PROVIDER_MAX_BUCKETS];
};

uint64_t twq_pressure_provider_monotonic_time_ns(void);
uint64_t twq_pressure_provider_sum_values(const uint64_t *values, size_t count);
uint64_t twq_pressure_provider_delta_or_zero_u64(uint64_t current, uint64_t base);
uint64_t twq_pressure_provider_nonidle_workers_u64(uint64_t total, uint64_t idle);
int twq_pressure_provider_read_snapshot_v1(struct twq_pressure_provider_snapshot_v1 *snapshot);

#endif
