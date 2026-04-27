#include "pthread_workqueue_pressure_snapshot_np.h"
#include "tbbx_twq_bridge_demand.h"

#include <errno.h>
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static uint32_t
default_platform_concurrency(void)
{
	long cpus;

	cpus = sysconf(_SC_NPROCESSORS_ONLN);
	if (cpus < 1)
		return (1);
	if (cpus > UINT32_MAX)
		return (UINT32_MAX);
	return ((uint32_t)cpus);
}

static uint32_t
parse_u32_arg(const char *value, const char *name)
{
	char *end;
	unsigned long parsed;

	parsed = strtoul(value, &end, 10);
	if (value[0] == '\0' || *end != '\0' || parsed > UINT32_MAX) {
		fprintf(stderr, "invalid %s: %s\n", name, value);
		exit(64);
	}
	return ((uint32_t)parsed);
}

static void
usage(FILE *stream)
{
	fprintf(stream,
	    "usage: pthread-workqueue-pressure-snapshot-np-probe "
	    "[--platform-concurrency N] [--previous-demand N]\n");
}

int
main(int argc, char **argv)
{
	struct _pthread_workqueue_pressure_snapshot_v1 snapshot;
	struct tbbx_twq_bridge_demand_v1 demand;
	uint32_t platform_concurrency, previous_demand;
	int error, i;

	platform_concurrency = default_platform_concurrency();
	previous_demand = 0;

	for (i = 1; i < argc; i++) {
		if (strcmp(argv[i], "--platform-concurrency") == 0) {
			if (++i >= argc) {
				usage(stderr);
				return (64);
			}
			platform_concurrency = parse_u32_arg(argv[i],
			    "platform concurrency");
		} else if (strcmp(argv[i], "--previous-demand") == 0) {
			if (++i >= argc) {
				usage(stderr);
				return (64);
			}
			previous_demand = parse_u32_arg(argv[i],
			    "previous demand");
		} else if (strcmp(argv[i], "--help") == 0 ||
		    strcmp(argv[i], "-h") == 0) {
			usage(stdout);
			return (0);
		} else {
			usage(stderr);
			return (64);
		}
	}

	memset(&snapshot, 0, sizeof(snapshot));
	snapshot.struct_size = sizeof(snapshot);
	error = __pthread_workqueue_pressure_snapshot_np(&snapshot);
	if (error != 0) {
		printf("{\"kind\":\"pthread-workqueue-pressure-snapshot-np-probe\","
		    "\"status\":\"error\",\"data\":{\"rc\":%d},"
		    "\"meta\":{\"component\":\"c\","
		    "\"binary\":\"pthread-workqueue-pressure-snapshot-np-probe\"}}\n",
		    error);
		return (error == ENOENT ? 69 : 1);
	}

	error = tbbx_twq_bridge_build_demand_v1(&demand, &snapshot,
	    platform_concurrency, previous_demand);
	if (error != 0)
		return (1);

	printf("{\"kind\":\"pthread-workqueue-pressure-snapshot-np-probe\","
	    "\"status\":\"ok\",\"data\":{"
	    "\"snapshot_version\":%u,"
	    "\"snapshot_struct_size\":%zu,"
	    "\"generation\":%" PRIu64 ","
	    "\"timestamp_ns\":%" PRIu64 ","
	    "\"total_workers\":%u,"
	    "\"idle_workers\":%u,"
	    "\"nonidle_workers\":%u,"
	    "\"requested_workers\":%u,"
	    "\"admitted_workers\":%u,"
	    "\"blocked_workers\":%u,"
	    "\"unblocked_workers\":%u,"
	    "\"narrowed_events\":%u,"
	    "\"demand_version\":%u,"
	    "\"demand_struct_size\":%zu,"
	    "\"platform_concurrency\":%u,"
	    "\"previous_reserve_demand\":%u,"
	    "\"reserve_demand\":%u,"
	    "\"changed\":%s,"
	    "\"should_request\":%s,"
	    "\"should_deactivate\":%s},"
	    "\"meta\":{\"component\":\"c\","
	    "\"binary\":\"pthread-workqueue-pressure-snapshot-np-probe\"}}\n",
	    snapshot.version, snapshot.struct_size, snapshot.generation,
	    snapshot.timestamp_ns, snapshot.total_workers,
	    snapshot.idle_workers, snapshot.nonidle_workers,
	    snapshot.requested_workers, snapshot.admitted_workers,
	    snapshot.blocked_workers, snapshot.unblocked_workers,
	    snapshot.narrowed_events, demand.version, demand.struct_size,
	    demand.platform_concurrency, demand.previous_reserve_demand,
	    demand.reserve_demand, demand.changed ? "true" : "false",
	    demand.should_request ? "true" : "false",
	    demand.should_deactivate ? "true" : "false");
	return (0);
}
