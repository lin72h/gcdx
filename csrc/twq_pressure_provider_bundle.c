#include "twq_pressure_provider_bundle.h"

#include <errno.h>
#include <string.h>

static uint8_t
view_is_quiescent(const struct twq_pressure_provider_view_v1 *view)
{
	return (view->total_workers_current == 0 &&
	    view->nonidle_workers_current == 0);
}

static uint8_t
view_has_narrow_feedback(const struct twq_pressure_provider_view_v1 *view)
{
	return (view->should_narrow_true_total > 0);
}

void
twq_pressure_provider_bundle_init_v1(
    struct twq_pressure_provider_bundle_v1 *bundle)
{
	if (bundle == NULL)
		return;

	memset(bundle, 0, sizeof(*bundle));
	bundle->struct_size = sizeof(*bundle);
	bundle->version = TWQ_PRESSURE_PROVIDER_BUNDLE_VERSION;
	bundle->generation_contiguous = 1;
	bundle->monotonic_increasing = 1;
	twq_pressure_provider_session_init_v1(&bundle->session);
	twq_pressure_provider_observer_init_v1(&bundle->observer);
	twq_pressure_provider_tracker_init_v1(&bundle->tracker);
}

int
twq_pressure_provider_bundle_prime_v1(
    struct twq_pressure_provider_bundle_v1 *bundle)
{
	int error;

	if (bundle == NULL)
		return (EINVAL);
	if (bundle->version != TWQ_PRESSURE_PROVIDER_BUNDLE_VERSION ||
	    bundle->struct_size != sizeof(*bundle)) {
		twq_pressure_provider_bundle_init_v1(bundle);
	}

	error = twq_pressure_provider_session_prime_v1(&bundle->session);
	if (error != 0)
		return (error);

	twq_pressure_provider_observer_init_v1(&bundle->observer);
	twq_pressure_provider_tracker_init_v1(&bundle->tracker);
	memset(&bundle->current_view, 0, sizeof(bundle->current_view));
	bundle->source_session_struct_size = 0;
	bundle->source_session_version = 0;
	bundle->source_view_struct_size = 0;
	bundle->source_view_version = 0;
	bundle->source_observer_struct_size = 0;
	bundle->source_observer_version = 0;
	bundle->source_tracker_struct_size = 0;
	bundle->source_tracker_version = 0;
	bundle->sample_count = 0;
	bundle->generation_first = 0;
	bundle->generation_last = 0;
	bundle->monotonic_time_first_ns = 0;
	bundle->monotonic_time_last_ns = 0;
	bundle->generation_contiguous = 1;
	bundle->monotonic_increasing = 1;
	bundle->current_pressure_visible = 0;
	bundle->current_quiescent = 0;
	bundle->current_narrow_feedback = 0;
	return (0);
}

int
twq_pressure_provider_bundle_poll_v1(
    struct twq_pressure_provider_bundle_v1 *bundle)
{
	struct twq_pressure_provider_view_v1 view;
	int error;

	if (bundle == NULL)
		return (EINVAL);
	if (bundle->version != TWQ_PRESSURE_PROVIDER_BUNDLE_VERSION ||
	    bundle->struct_size != sizeof(*bundle))
		return (EPROTO);
	if (bundle->session.version != TWQ_PRESSURE_PROVIDER_SESSION_VERSION ||
	    bundle->session.struct_size != sizeof(bundle->session) ||
	    !bundle->session.primed)
		return (ENXIO);

	error = twq_pressure_provider_session_poll_v1(&bundle->session, &view);
	if (error != 0)
		return (error);

	if (bundle->observer.sample_count == 0) {
		bundle->observer.source_session_struct_size =
		    bundle->session.struct_size;
		bundle->observer.source_session_version = bundle->session.version;
	} else if (bundle->observer.source_session_struct_size !=
	    bundle->session.struct_size ||
	    bundle->observer.source_session_version != bundle->session.version) {
		return (EPROTO);
	}
	if (bundle->tracker.sample_count == 0) {
		bundle->tracker.source_session_struct_size =
		    bundle->session.struct_size;
		bundle->tracker.source_session_version = bundle->session.version;
	} else if (bundle->tracker.source_session_struct_size !=
	    bundle->session.struct_size ||
	    bundle->tracker.source_session_version != bundle->session.version) {
		return (EPROTO);
	}

	error = twq_pressure_provider_observer_update_v1(&bundle->observer, &view);
	if (error != 0)
		return (error);
	error = twq_pressure_provider_tracker_update_v1(&bundle->tracker, &view);
	if (error != 0)
		return (error);

	if (bundle->sample_count == 0) {
		bundle->source_session_struct_size = bundle->session.struct_size;
		bundle->source_session_version = bundle->session.version;
		bundle->source_view_struct_size = view.struct_size;
		bundle->source_view_version = view.version;
		bundle->source_observer_struct_size = bundle->observer.struct_size;
		bundle->source_observer_version = bundle->observer.version;
		bundle->source_tracker_struct_size = bundle->tracker.struct_size;
		bundle->source_tracker_version = bundle->tracker.version;
		bundle->generation_first = view.generation;
		bundle->monotonic_time_first_ns = view.monotonic_time_ns;
	} else {
		if (bundle->source_session_struct_size != bundle->session.struct_size ||
		    bundle->source_session_version != bundle->session.version ||
		    bundle->source_view_struct_size != view.struct_size ||
		    bundle->source_view_version != view.version ||
		    bundle->source_observer_struct_size != bundle->observer.struct_size ||
		    bundle->source_observer_version != bundle->observer.version ||
		    bundle->source_tracker_struct_size != bundle->tracker.struct_size ||
		    bundle->source_tracker_version != bundle->tracker.version)
			return (EPROTO);
		if (view.generation != bundle->generation_last + 1)
			bundle->generation_contiguous = 0;
		if (view.monotonic_time_ns <= bundle->monotonic_time_last_ns)
			bundle->monotonic_increasing = 0;
	}

	bundle->sample_count++;
	bundle->generation_last = view.generation;
	bundle->monotonic_time_last_ns = view.monotonic_time_ns;
	bundle->current_pressure_visible = view.pressure_visible ? 1 : 0;
	bundle->current_quiescent = view_is_quiescent(&view) ? 1 : 0;
	bundle->current_narrow_feedback = view_has_narrow_feedback(&view) ? 1 : 0;
	bundle->current_view = view;
	return (0);
}
