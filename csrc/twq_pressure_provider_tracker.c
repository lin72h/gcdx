#include "twq_pressure_provider_tracker.h"
#include "twq_pressure_provider_session.h"

#include <errno.h>
#include <string.h>

static uint8_t
view_is_nonidle(const struct twq_pressure_provider_view_v1 *view)
{
	return (view->nonidle_workers_current > 0);
}

static uint8_t
view_has_request_backlog(const struct twq_pressure_provider_view_v1 *view)
{
	return (view->request_backlog_total > 0);
}

static uint8_t
view_has_block_backlog(const struct twq_pressure_provider_view_v1 *view)
{
	return (view->block_backlog_total > 0);
}

static uint8_t
view_has_narrow_feedback(const struct twq_pressure_provider_view_v1 *view)
{
	return (view->should_narrow_true_total > 0);
}

static uint8_t
view_is_quiescent(const struct twq_pressure_provider_view_v1 *view)
{
	return (view->total_workers_current == 0 &&
	    view->nonidle_workers_current == 0);
}

static void
count_edge(uint64_t *rises, uint64_t *falls, uint8_t previous, uint8_t current)
{
	if (!previous && current)
		(*rises)++;
	else if (previous && !current)
		(*falls)++;
}

void
twq_pressure_provider_tracker_init_v1(
    struct twq_pressure_provider_tracker_v1 *tracker)
{
	if (tracker == NULL)
		return;

	memset(tracker, 0, sizeof(*tracker));
	tracker->struct_size = sizeof(*tracker);
	tracker->version = TWQ_PRESSURE_PROVIDER_TRACKER_VERSION;
	tracker->generation_contiguous = 1;
	tracker->monotonic_increasing = 1;
}

int
twq_pressure_provider_tracker_update_v1(
    struct twq_pressure_provider_tracker_v1 *tracker,
    const struct twq_pressure_provider_view_v1 *view)
{
	uint8_t pressure_visible, nonidle, request_backlog, block_backlog;
	uint8_t narrow_feedback, quiescent;

	if (tracker == NULL || view == NULL)
		return (EINVAL);
	if (view->version != TWQ_PRESSURE_PROVIDER_ADAPTER_VERSION)
		return (EPROTO);

	if (tracker->version != TWQ_PRESSURE_PROVIDER_TRACKER_VERSION ||
	    tracker->struct_size != sizeof(*tracker)) {
		twq_pressure_provider_tracker_init_v1(tracker);
	}

	pressure_visible = view->pressure_visible ? 1 : 0;
	nonidle = view_is_nonidle(view);
	request_backlog = view_has_request_backlog(view);
	block_backlog = view_has_block_backlog(view);
	narrow_feedback = view_has_narrow_feedback(view);
	quiescent = view_is_quiescent(view);

	if (tracker->sample_count == 0) {
		tracker->source_view_struct_size = view->struct_size;
		tracker->source_view_version = view->version;
		tracker->generation_first = view->generation;
		tracker->monotonic_time_first_ns = view->monotonic_time_ns;
		tracker->initial_pressure_visible = pressure_visible;
		tracker->initial_nonidle = nonidle;
		tracker->initial_request_backlog = request_backlog;
		tracker->initial_block_backlog = block_backlog;
		tracker->initial_narrow_feedback = narrow_feedback;
		tracker->initial_quiescent = quiescent;
	} else {
		if (tracker->source_view_struct_size != view->struct_size ||
		    tracker->source_view_version != view->version)
			return (EPROTO);
		if (view->generation != tracker->generation_last + 1)
			tracker->generation_contiguous = 0;
		if (view->monotonic_time_ns <= tracker->monotonic_time_last_ns)
			tracker->monotonic_increasing = 0;

		count_edge(&tracker->pressure_visible_rises,
		    &tracker->pressure_visible_falls,
		    tracker->final_pressure_visible, pressure_visible);
		count_edge(&tracker->nonidle_rises, &tracker->nonidle_falls,
		    tracker->final_nonidle, nonidle);
		count_edge(&tracker->request_backlog_rises,
		    &tracker->request_backlog_falls,
		    tracker->final_request_backlog, request_backlog);
		count_edge(&tracker->block_backlog_rises,
		    &tracker->block_backlog_falls,
		    tracker->final_block_backlog, block_backlog);
		count_edge(&tracker->narrow_feedback_rises,
		    &tracker->narrow_feedback_falls,
		    tracker->final_narrow_feedback, narrow_feedback);
		count_edge(&tracker->quiescent_rises, &tracker->quiescent_falls,
		    tracker->final_quiescent, quiescent);
	}

	tracker->sample_count++;
	tracker->generation_last = view->generation;
	tracker->monotonic_time_last_ns = view->monotonic_time_ns;
	tracker->final_pressure_visible = pressure_visible;
	tracker->final_nonidle = nonidle;
	tracker->final_request_backlog = request_backlog;
	tracker->final_block_backlog = block_backlog;
	tracker->final_narrow_feedback = narrow_feedback;
	tracker->final_quiescent = quiescent;
	return (0);
}

int
twq_pressure_provider_tracker_poll_session_v1(
    struct twq_pressure_provider_tracker_v1 *tracker,
    struct twq_pressure_provider_session_v1 *session)
{
	struct twq_pressure_provider_view_v1 view;
	int error;

	if (tracker == NULL || session == NULL)
		return (EINVAL);
	if (session->version != TWQ_PRESSURE_PROVIDER_SESSION_VERSION ||
	    session->struct_size != sizeof(*session))
		return (EPROTO);
	if (tracker->version != TWQ_PRESSURE_PROVIDER_TRACKER_VERSION ||
	    tracker->struct_size != sizeof(*tracker)) {
		twq_pressure_provider_tracker_init_v1(tracker);
	}

	error = twq_pressure_provider_session_poll_v1(session, &view);
	if (error != 0)
		return (error);

	if (tracker->sample_count == 0) {
		tracker->source_session_struct_size = session->struct_size;
		tracker->source_session_version = session->version;
	} else if (tracker->source_session_struct_size != session->struct_size ||
	    tracker->source_session_version != session->version) {
		return (EPROTO);
	}

	return (twq_pressure_provider_tracker_update_v1(tracker, &view));
}
