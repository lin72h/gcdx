#include "twq_pressure_provider_session.h"

#include <errno.h>
#include <string.h>

void
twq_pressure_provider_session_init_v1(
    struct twq_pressure_provider_session_v1 *session)
{
	if (session == NULL)
		return;

	memset(session, 0, sizeof(*session));
	session->struct_size = sizeof(*session);
	session->version = TWQ_PRESSURE_PROVIDER_SESSION_VERSION;
	session->next_generation = 1;
}

int
twq_pressure_provider_session_prime_v1(
    struct twq_pressure_provider_session_v1 *session)
{
	int error;

	if (session == NULL)
		return (EINVAL);

	twq_pressure_provider_session_init_v1(session);
	error = twq_pressure_provider_read_snapshot_v1(&session->base_snapshot);
	if (error != 0)
		return (error);

	session->source_snapshot_struct_size =
	    session->base_snapshot.struct_size;
	session->source_snapshot_version = session->base_snapshot.version;
	session->bucket_count = session->base_snapshot.bucket_count;
	session->primed = 1;
	return (0);
}

int
twq_pressure_provider_session_poll_v1(
    struct twq_pressure_provider_session_v1 *session,
    struct twq_pressure_provider_view_v1 *view)
{
	struct twq_pressure_provider_snapshot_v1 current_snapshot;
	int error;

	if (session == NULL || view == NULL)
		return (EINVAL);
	if (session->version != TWQ_PRESSURE_PROVIDER_SESSION_VERSION ||
	    session->struct_size != sizeof(*session))
		return (EPROTO);
	if (!session->primed)
		return (ENXIO);

	error = twq_pressure_provider_read_snapshot_v1(&current_snapshot);
	if (error != 0)
		return (error);
	error = twq_pressure_provider_adapter_build_v1(view,
	    session->next_generation, &session->base_snapshot, &current_snapshot);
	if (error != 0)
		return (error);

	session->next_generation++;
	return (0);
}
