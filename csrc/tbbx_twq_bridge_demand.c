#include "tbbx_twq_bridge_demand.h"

#include <errno.h>
#include <string.h>

static uint32_t
min_u32(uint32_t lhs, uint32_t rhs)
{
	return (lhs < rhs ? lhs : rhs);
}

uint32_t
tbbx_twq_bridge_wrapping_delta_u32(uint32_t current, uint32_t previous)
{
	return ((uint32_t)(current - previous));
}

uint32_t
tbbx_twq_bridge_reserve_demand_v1(
    const struct _pthread_workqueue_pressure_snapshot_v1 *snapshot,
    uint32_t platform_concurrency)
{
	if (snapshot == NULL || platform_concurrency == 0)
		return (0);
	return (min_u32(snapshot->nonidle_workers, platform_concurrency));
}

int
tbbx_twq_bridge_build_demand_v1(
    struct tbbx_twq_bridge_demand_v1 *demand,
    const struct _pthread_workqueue_pressure_snapshot_v1 *snapshot,
    uint32_t platform_concurrency, uint32_t previous_reserve_demand)
{
	uint32_t reserve_demand;

	if (demand == NULL || snapshot == NULL)
		return (EINVAL);

	reserve_demand = tbbx_twq_bridge_reserve_demand_v1(snapshot,
	    platform_concurrency);

	memset(demand, 0, sizeof(*demand));
	demand->struct_size = sizeof(*demand);
	demand->version = TBBX_TWQ_BRIDGE_DEMAND_VERSION;
	demand->platform_concurrency = platform_concurrency;
	demand->previous_reserve_demand = previous_reserve_demand;
	demand->nonidle_workers = snapshot->nonidle_workers;
	demand->reserve_demand = reserve_demand;
	demand->changed = reserve_demand != previous_reserve_demand ? 1 : 0;
	demand->should_request = reserve_demand > 0 &&
	    reserve_demand != previous_reserve_demand ? 1 : 0;
	demand->should_deactivate = reserve_demand == 0 &&
	    previous_reserve_demand != 0 ? 1 : 0;
	return (0);
}
