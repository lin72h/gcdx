#ifndef TBBX_TWQ_BRIDGE_DEMAND_H
#define TBBX_TWQ_BRIDGE_DEMAND_H

#include "pthread_workqueue_pressure_snapshot_np.h"

#include <stddef.h>
#include <stdint.h>

#define TBBX_TWQ_BRIDGE_DEMAND_VERSION 1U

/*
 * Adapter-side demand projection.  This is deliberately TCM-header-free; the
 * TBBX side owns translating the result into tcmRequestPermit /
 * tcmDeactivatePermit calls.
 */
struct tbbx_twq_bridge_demand_v1 {
	size_t struct_size;
	uint32_t version;
	uint32_t platform_concurrency;
	uint32_t previous_reserve_demand;
	uint32_t nonidle_workers;
	uint32_t reserve_demand;
	uint8_t changed;
	uint8_t should_request;
	uint8_t should_deactivate;
	uint8_t reserved_flags;
	uint32_t reserved[6];
};

uint32_t tbbx_twq_bridge_wrapping_delta_u32(uint32_t current,
    uint32_t previous);
uint32_t tbbx_twq_bridge_reserve_demand_v1(
    const struct _pthread_workqueue_pressure_snapshot_v1 *snapshot,
    uint32_t platform_concurrency);
int tbbx_twq_bridge_build_demand_v1(
    struct tbbx_twq_bridge_demand_v1 *demand,
    const struct _pthread_workqueue_pressure_snapshot_v1 *snapshot,
    uint32_t platform_concurrency, uint32_t previous_reserve_demand);

#endif
