#ifndef TWQ_PRESSURE_PROVIDER_BUNDLE_H
#define TWQ_PRESSURE_PROVIDER_BUNDLE_H

#include "twq_pressure_provider_observer.h"
#include "twq_pressure_provider_session.h"
#include "twq_pressure_provider_tracker.h"

#include <stddef.h>
#include <stdint.h>

#define TWQ_PRESSURE_PROVIDER_BUNDLE_VERSION 1U

struct twq_pressure_provider_bundle_v1 {
	size_t struct_size;
	uint32_t version;
	size_t source_session_struct_size;
	uint32_t source_session_version;
	size_t source_view_struct_size;
	uint32_t source_view_version;
	size_t source_observer_struct_size;
	uint32_t source_observer_version;
	size_t source_tracker_struct_size;
	uint32_t source_tracker_version;
	uint64_t sample_count;
	uint64_t generation_first;
	uint64_t generation_last;
	uint64_t monotonic_time_first_ns;
	uint64_t monotonic_time_last_ns;
	uint8_t generation_contiguous;
	uint8_t monotonic_increasing;
	uint8_t current_pressure_visible;
	uint8_t current_quiescent;
	uint8_t current_narrow_feedback;
	struct twq_pressure_provider_view_v1 current_view;
	struct twq_pressure_provider_observer_v1 observer;
	struct twq_pressure_provider_tracker_v1 tracker;
	struct twq_pressure_provider_session_v1 session;
};

void twq_pressure_provider_bundle_init_v1(
    struct twq_pressure_provider_bundle_v1 *bundle);
int twq_pressure_provider_bundle_prime_v1(
    struct twq_pressure_provider_bundle_v1 *bundle);
int twq_pressure_provider_bundle_poll_v1(
    struct twq_pressure_provider_bundle_v1 *bundle);

#endif
