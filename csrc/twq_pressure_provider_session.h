#ifndef TWQ_PRESSURE_PROVIDER_SESSION_H
#define TWQ_PRESSURE_PROVIDER_SESSION_H

#include "twq_pressure_provider_adapter.h"

#include <stddef.h>
#include <stdint.h>

#define TWQ_PRESSURE_PROVIDER_SESSION_VERSION 1U

struct twq_pressure_provider_session_v1 {
	size_t struct_size;
	uint32_t version;
	size_t source_snapshot_struct_size;
	uint32_t source_snapshot_version;
	uint32_t bucket_count;
	uint64_t next_generation;
	uint8_t primed;
	struct twq_pressure_provider_snapshot_v1 base_snapshot;
};

void twq_pressure_provider_session_init_v1(
    struct twq_pressure_provider_session_v1 *session);
int twq_pressure_provider_session_prime_v1(
    struct twq_pressure_provider_session_v1 *session);
int twq_pressure_provider_session_poll_v1(
    struct twq_pressure_provider_session_v1 *session,
    struct twq_pressure_provider_view_v1 *view);

#endif
