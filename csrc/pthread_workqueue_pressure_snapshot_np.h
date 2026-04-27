#ifndef PTHREAD_WORKQUEUE_PRESSURE_SNAPSHOT_NP_H
#define PTHREAD_WORKQUEUE_PRESSURE_SNAPSHOT_NP_H

#include <stddef.h>
#include <stdint.h>

#define PTHREAD_WORKQUEUE_PRESSURE_SNAPSHOT_VERSION 1U

/*
 * Candidate compact private-SPI shape for the future libthr provider.
 *
 * This header is a local GCDX/TBBX handoff artifact.  It is not installed by
 * libthr and does not claim that the real SPI is frozen.
 */
struct _pthread_workqueue_pressure_snapshot_v1 {
	size_t struct_size;
	uint32_t version;
	uint32_t _pad0;
	uint64_t generation;
	uint64_t timestamp_ns;

	uint32_t total_workers;
	uint32_t idle_workers;
	uint32_t nonidle_workers;

	uint32_t requested_workers;
	uint32_t admitted_workers;
	uint32_t blocked_workers;
	uint32_t unblocked_workers;
	uint32_t narrowed_events;

	uint32_t reserved[6];
};

int __pthread_workqueue_pressure_snapshot_np(
    struct _pthread_workqueue_pressure_snapshot_v1 *snapshot);

#endif
