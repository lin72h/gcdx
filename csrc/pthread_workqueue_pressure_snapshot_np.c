#include "pthread_workqueue_pressure_snapshot_np.h"

#include "twq_pressure_provider_preview.h"

#include <errno.h>
#include <stdatomic.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>

static atomic_uint_fast64_t next_generation = 1;

static uint32_t
low_u32(uint64_t value)
{
	return ((uint32_t)value);
}

static int
field_fits(size_t caller_size, size_t offset, size_t field_size)
{
	return (caller_size >= offset + field_size);
}

#define FILL_FIELD(snapshot, caller_size, field, value)			\
	do {								\
		if (field_fits((caller_size),				\
		    offsetof(struct _pthread_workqueue_pressure_snapshot_v1,	\
		    field), sizeof((snapshot)->field))) {		\
			(snapshot)->field = (value);			\
		}							\
	} while (0)

int
__pthread_workqueue_pressure_snapshot_np(
    struct _pthread_workqueue_pressure_snapshot_v1 *snapshot)
{
	struct twq_pressure_provider_snapshot_v1 preview;
	uint64_t generation;
	size_t caller_size;
	int error;

	if (snapshot == NULL)
		return (EINVAL);

	caller_size = snapshot->struct_size;
	if (caller_size < sizeof(snapshot->struct_size))
		return (EINVAL);

	memset(snapshot, 0, caller_size);
	FILL_FIELD(snapshot, caller_size, struct_size, sizeof(*snapshot));
	FILL_FIELD(snapshot, caller_size, version,
	    PTHREAD_WORKQUEUE_PRESSURE_SNAPSHOT_VERSION);

	error = twq_pressure_provider_read_snapshot_v1(&preview);
	if (error != 0)
		return (error);

	generation = atomic_fetch_add_explicit(&next_generation, 1,
	    memory_order_relaxed);

	FILL_FIELD(snapshot, caller_size, generation, generation);
	FILL_FIELD(snapshot, caller_size, timestamp_ns,
	    preview.monotonic_time_ns);
	FILL_FIELD(snapshot, caller_size, total_workers,
	    low_u32(preview.total_workers_current));
	FILL_FIELD(snapshot, caller_size, idle_workers,
	    low_u32(preview.idle_workers_current));
	FILL_FIELD(snapshot, caller_size, nonidle_workers,
	    low_u32(preview.nonidle_workers_current));
	FILL_FIELD(snapshot, caller_size, requested_workers,
	    low_u32(preview.requested_workers_total));
	FILL_FIELD(snapshot, caller_size, admitted_workers,
	    low_u32(preview.admitted_workers_total));
	FILL_FIELD(snapshot, caller_size, blocked_workers,
	    low_u32(preview.blocked_workers_total));
	FILL_FIELD(snapshot, caller_size, unblocked_workers,
	    low_u32(preview.unblocked_workers_total));
	FILL_FIELD(snapshot, caller_size, narrowed_events,
	    low_u32(preview.should_narrow_true_count));

	return (0);
}
