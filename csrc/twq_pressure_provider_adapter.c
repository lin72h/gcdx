#include "twq_pressure_provider_adapter.h"

#include <errno.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>

static uint64_t
sum_bucket_deltas(const uint64_t *current, const uint64_t *base, size_t count)
{
	uint64_t sum;
	size_t i;

	sum = 0;
	for (i = 0; i < count; i++) {
		sum += twq_pressure_provider_delta_or_zero_u64(current[i], base[i]);
	}
	return (sum);
}

int
twq_pressure_provider_adapter_build_v1(struct twq_pressure_provider_view_v1 *view,
    uint64_t generation, const struct twq_pressure_provider_snapshot_v1 *base,
    const struct twq_pressure_provider_snapshot_v1 *current)
{
	uint64_t requested_workers_total, admitted_workers_total;
	uint64_t blocked_workers_total, unblocked_workers_total;

	if (view == NULL || base == NULL || current == NULL)
		return (EINVAL);
	if (base->version != TWQ_PRESSURE_PROVIDER_PREVIEW_VERSION ||
	    current->version != TWQ_PRESSURE_PROVIDER_PREVIEW_VERSION)
		return (EPROTO);
	if (base->bucket_count != current->bucket_count)
		return (EPROTO);
	if (current->bucket_count > TWQ_PRESSURE_PROVIDER_MAX_BUCKETS)
		return (E2BIG);

	memset(view, 0, sizeof(*view));

	requested_workers_total = sum_bucket_deltas(current->bucket_req_total,
	    base->bucket_req_total, current->bucket_count);
	admitted_workers_total = sum_bucket_deltas(current->bucket_admit_total,
	    base->bucket_admit_total, current->bucket_count);
	blocked_workers_total = sum_bucket_deltas(
	    current->bucket_switch_block_total,
	    base->bucket_switch_block_total, current->bucket_count);
	unblocked_workers_total = sum_bucket_deltas(
	    current->bucket_switch_unblock_total,
	    base->bucket_switch_unblock_total, current->bucket_count);

	view->struct_size = sizeof(*view);
	view->version = TWQ_PRESSURE_PROVIDER_ADAPTER_VERSION;
	view->generation = generation;
	view->monotonic_time_ns = current->monotonic_time_ns;
	view->request_events_total = twq_pressure_provider_delta_or_zero_u64(
	    current->reqthreads_count, base->reqthreads_count);
	view->worker_entries_total = twq_pressure_provider_delta_or_zero_u64(
	    current->thread_enter_count, base->thread_enter_count);
	view->worker_returns_total = twq_pressure_provider_delta_or_zero_u64(
	    current->thread_return_count, base->thread_return_count);
	view->requested_workers_total = requested_workers_total;
	view->admitted_workers_total = admitted_workers_total;
	view->blocked_events_total = twq_pressure_provider_delta_or_zero_u64(
	    current->switch_block_count, base->switch_block_count);
	view->unblocked_events_total = twq_pressure_provider_delta_or_zero_u64(
	    current->switch_unblock_count, base->switch_unblock_count);
	view->blocked_workers_total = blocked_workers_total;
	view->unblocked_workers_total = unblocked_workers_total;
	view->total_workers_current = current->total_workers_current;
	view->idle_workers_current = current->idle_workers_current;
	view->nonidle_workers_current = current->nonidle_workers_current;
	view->active_workers_current = current->active_workers_current;
	view->should_narrow_true_total = twq_pressure_provider_delta_or_zero_u64(
	    current->should_narrow_true_count, base->should_narrow_true_count);
	view->request_backlog_total =
	    requested_workers_total >= admitted_workers_total ?
	    requested_workers_total - admitted_workers_total : 0;
	view->block_backlog_total =
	    blocked_workers_total >= unblocked_workers_total ?
	    blocked_workers_total - unblocked_workers_total : 0;
	view->has_per_bucket_diagnostics = 0;
	view->has_admission_feedback = 1;
	view->has_block_feedback = 1;
	view->has_live_current_counts = 1;
	view->has_narrow_feedback = 1;
	view->pressure_visible = view->request_backlog_total > 0 ||
	    view->block_backlog_total > 0 ||
	    view->should_narrow_true_total > 0 ||
	    view->nonidle_workers_current > 0;
	return (0);
}
