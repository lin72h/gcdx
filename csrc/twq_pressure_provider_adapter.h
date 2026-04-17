#ifndef TWQ_PRESSURE_PROVIDER_ADAPTER_H
#define TWQ_PRESSURE_PROVIDER_ADAPTER_H

#include "twq_pressure_provider_preview.h"

#include <stddef.h>
#include <stdint.h>

#define TWQ_PRESSURE_PROVIDER_ADAPTER_VERSION 1U

struct twq_pressure_provider_view_v1 {
	size_t struct_size;
	uint32_t version;
	uint64_t generation;
	uint64_t monotonic_time_ns;
	uint64_t request_events_total;
	uint64_t worker_entries_total;
	uint64_t worker_returns_total;
	uint64_t requested_workers_total;
	uint64_t admitted_workers_total;
	uint64_t blocked_events_total;
	uint64_t unblocked_events_total;
	uint64_t blocked_workers_total;
	uint64_t unblocked_workers_total;
	uint64_t total_workers_current;
	uint64_t idle_workers_current;
	uint64_t nonidle_workers_current;
	uint64_t active_workers_current;
	uint64_t should_narrow_true_total;
	uint64_t request_backlog_total;
	uint64_t block_backlog_total;
	uint8_t has_per_bucket_diagnostics;
	uint8_t has_admission_feedback;
	uint8_t has_block_feedback;
	uint8_t has_live_current_counts;
	uint8_t has_narrow_feedback;
	uint8_t pressure_visible;
};

int twq_pressure_provider_adapter_build_v1(
    struct twq_pressure_provider_view_v1 *view, uint64_t generation,
    const struct twq_pressure_provider_snapshot_v1 *base,
    const struct twq_pressure_provider_snapshot_v1 *current);

#endif
