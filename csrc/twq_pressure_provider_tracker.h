#ifndef TWQ_PRESSURE_PROVIDER_TRACKER_H
#define TWQ_PRESSURE_PROVIDER_TRACKER_H

#include "twq_pressure_provider_adapter.h"

#include <stddef.h>
#include <stdint.h>

#define TWQ_PRESSURE_PROVIDER_TRACKER_VERSION 1U

struct twq_pressure_provider_session_v1;

struct twq_pressure_provider_tracker_v1 {
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
	uint64_t pressure_visible_rises;
	uint64_t pressure_visible_falls;
	uint64_t nonidle_rises;
	uint64_t nonidle_falls;
	uint64_t request_backlog_rises;
	uint64_t request_backlog_falls;
	uint64_t block_backlog_rises;
	uint64_t block_backlog_falls;
	uint64_t narrow_feedback_rises;
	uint64_t narrow_feedback_falls;
	uint64_t quiescent_rises;
	uint64_t quiescent_falls;
	uint8_t generation_contiguous;
	uint8_t monotonic_increasing;
	uint8_t initial_pressure_visible;
	uint8_t initial_nonidle;
	uint8_t initial_request_backlog;
	uint8_t initial_block_backlog;
	uint8_t initial_narrow_feedback;
	uint8_t initial_quiescent;
	uint8_t final_pressure_visible;
	uint8_t final_nonidle;
	uint8_t final_request_backlog;
	uint8_t final_block_backlog;
	uint8_t final_narrow_feedback;
	uint8_t final_quiescent;
};

void twq_pressure_provider_tracker_init_v1(
    struct twq_pressure_provider_tracker_v1 *tracker);
int twq_pressure_provider_tracker_update_v1(
    struct twq_pressure_provider_tracker_v1 *tracker,
    const struct twq_pressure_provider_view_v1 *view);
int twq_pressure_provider_tracker_poll_session_v1(
    struct twq_pressure_provider_tracker_v1 *tracker,
    struct twq_pressure_provider_session_v1 *session);

#endif
