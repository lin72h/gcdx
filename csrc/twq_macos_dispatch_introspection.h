#ifndef TWQ_MACOS_DISPATCH_INTROSPECTION_H
#define TWQ_MACOS_DISPATCH_INTROSPECTION_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

struct twq_macos_dispatch_counters {
	uint64_t root_push_total_default;
	uint64_t root_push_empty_default;
	uint64_t root_push_source_default;
	uint64_t root_push_continuation_default;
	uint64_t root_poke_slow_default;
	uint64_t root_requested_threads_default;

	uint64_t root_push_total_default_overcommit;
	uint64_t root_push_empty_default_overcommit;
	uint64_t root_push_mainq_default_overcommit;
	uint64_t root_push_continuation_default_overcommit;
	uint64_t root_poke_slow_default_overcommit;
	uint64_t root_requested_threads_default_overcommit;

	uint64_t pthread_workqueue_addthreads_calls;
	uint64_t pthread_workqueue_addthreads_requested_threads;
};

int twq_macos_dispatch_introspection_install(void);
void twq_macos_dispatch_introspection_reset(void);
int twq_macos_dispatch_introspection_snapshot(
		struct twq_macos_dispatch_counters *out);
int twq_macos_dispatch_introspection_available(void);
const char *twq_macos_dispatch_introspection_last_error(void);

#ifdef __cplusplus
}
#endif

#endif
