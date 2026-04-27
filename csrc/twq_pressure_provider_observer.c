#include "twq_pressure_provider_observer.h"
#include "twq_pressure_provider_session.h"

#include <errno.h>
#include <string.h>

static uint64_t
max_u64(uint64_t lhs, uint64_t rhs)
{
	return (lhs >= rhs ? lhs : rhs);
}

static uint8_t
view_is_quiescent(const struct twq_pressure_provider_view_v1 *view)
{
	return (view->total_workers_current == 0 &&
	    view->nonidle_workers_current == 0);
}

void
twq_pressure_provider_observer_init_v1(
    struct twq_pressure_provider_observer_v1 *observer)
{
	if (observer == NULL)
		return;

	memset(observer, 0, sizeof(*observer));
	observer->struct_size = sizeof(*observer);
	observer->version = TWQ_PRESSURE_PROVIDER_OBSERVER_VERSION;
	observer->generation_contiguous = 1;
	observer->monotonic_increasing = 1;
}

int
twq_pressure_provider_observer_update_v1(
    struct twq_pressure_provider_observer_v1 *observer,
    const struct twq_pressure_provider_view_v1 *view)
{
	uint8_t quiescent;

	if (observer == NULL || view == NULL)
		return (EINVAL);
	if (view->version != TWQ_PRESSURE_PROVIDER_ADAPTER_VERSION)
		return (EPROTO);

	if (observer->version != TWQ_PRESSURE_PROVIDER_OBSERVER_VERSION ||
	    observer->struct_size != sizeof(*observer)) {
		twq_pressure_provider_observer_init_v1(observer);
	}

	if (observer->sample_count == 0) {
		observer->source_view_struct_size = view->struct_size;
		observer->source_view_version = view->version;
		observer->generation_first = view->generation;
		observer->monotonic_time_first_ns = view->monotonic_time_ns;
	} else {
		if (observer->source_view_struct_size != view->struct_size ||
		    observer->source_view_version != view->version)
			return (EPROTO);
		if (view->generation != observer->generation_last + 1)
			observer->generation_contiguous = 0;
		if (view->monotonic_time_ns <= observer->monotonic_time_last_ns)
			observer->monotonic_increasing = 0;
	}

	quiescent = view_is_quiescent(view);

	observer->sample_count++;
	observer->generation_last = view->generation;
	observer->monotonic_time_last_ns = view->monotonic_time_ns;
	observer->pressure_visible_samples += view->pressure_visible ? 1 : 0;
	observer->nonidle_samples += view->nonidle_workers_current > 0 ? 1 : 0;
	observer->request_backlog_samples += view->request_backlog_total > 0 ? 1 : 0;
	observer->block_backlog_samples += view->block_backlog_total > 0 ? 1 : 0;
	observer->narrow_feedback_samples +=
	    view->should_narrow_true_total > 0 ? 1 : 0;
	observer->quiescent_samples += quiescent ? 1 : 0;
	observer->max_nonidle_workers_current = max_u64(
	    observer->max_nonidle_workers_current,
	    view->nonidle_workers_current);
	observer->max_request_backlog_total = max_u64(
	    observer->max_request_backlog_total,
	    view->request_backlog_total);
	observer->max_block_backlog_total = max_u64(
	    observer->max_block_backlog_total,
	    view->block_backlog_total);
	observer->final_total_workers_current = view->total_workers_current;
	observer->final_idle_workers_current = view->idle_workers_current;
	observer->final_nonidle_workers_current = view->nonidle_workers_current;
	observer->final_active_workers_current = view->active_workers_current;
	observer->final_pressure_visible = view->pressure_visible ? 1 : 0;
	observer->final_quiescent = quiescent ? 1 : 0;
	return (0);
}

int
twq_pressure_provider_observer_poll_session_v1(
    struct twq_pressure_provider_observer_v1 *observer,
    struct twq_pressure_provider_session_v1 *session)
{
	struct twq_pressure_provider_view_v1 view;
	int error;

	if (observer == NULL || session == NULL)
		return (EINVAL);
	if (session->version != TWQ_PRESSURE_PROVIDER_SESSION_VERSION ||
	    session->struct_size != sizeof(*session))
		return (EPROTO);
	if (observer->version != TWQ_PRESSURE_PROVIDER_OBSERVER_VERSION ||
	    observer->struct_size != sizeof(*observer)) {
		twq_pressure_provider_observer_init_v1(observer);
	}

	error = twq_pressure_provider_session_poll_v1(session, &view);
	if (error != 0)
		return (error);

	if (observer->sample_count == 0) {
		observer->source_session_struct_size = session->struct_size;
		observer->source_session_version = session->version;
	} else if (observer->source_session_struct_size != session->struct_size ||
	    observer->source_session_version != session->version) {
		return (EPROTO);
	}

	return (twq_pressure_provider_observer_update_v1(observer, &view));
}
