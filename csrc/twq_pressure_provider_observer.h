#ifndef TWQ_PRESSURE_PROVIDER_OBSERVER_H
#define TWQ_PRESSURE_PROVIDER_OBSERVER_H

#include "twq_pressure_provider_adapter.h"

#include <stddef.h>
#include <stdint.h>

#define TWQ_PRESSURE_PROVIDER_OBSERVER_VERSION 1U

struct twq_pressure_provider_session_v1;

struct twq_pressure_provider_observer_v1 {
	size_t struct_size;
	uint32_t version;
	size_t source_session_struct_size;
	uint32_t source_session_version;
	size_t source_view_struct_size;
	uint32_t source_view_version;
	uint64_t sample_count;
	uint64_t generation_first;
	uint64_t generation_last;
	uint64_t monotonic_time_first_ns;
	uint64_t monotonic_time_last_ns;
	uint64_t pressure_visible_samples;
	uint64_t nonidle_samples;
	uint64_t request_backlog_samples;
	uint64_t block_backlog_samples;
	uint64_t narrow_feedback_samples;
	uint64_t quiescent_samples;
	uint64_t max_nonidle_workers_current;
	uint64_t max_request_backlog_total;
	uint64_t max_block_backlog_total;
	uint64_t final_total_workers_current;
	uint64_t final_idle_workers_current;
	uint64_t final_nonidle_workers_current;
	uint64_t final_active_workers_current;
	uint8_t generation_contiguous;
	uint8_t monotonic_increasing;
	uint8_t final_pressure_visible;
	uint8_t final_quiescent;
};

void twq_pressure_provider_observer_init_v1(
    struct twq_pressure_provider_observer_v1 *observer);
int twq_pressure_provider_observer_update_v1(
    struct twq_pressure_provider_observer_v1 *observer,
    const struct twq_pressure_provider_view_v1 *view);
int twq_pressure_provider_observer_poll_session_v1(
    struct twq_pressure_provider_observer_v1 *observer,
    struct twq_pressure_provider_session_v1 *session);

#endif
