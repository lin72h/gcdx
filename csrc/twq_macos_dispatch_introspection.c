#include "twq_macos_dispatch_introspection.h"

#include <dispatch/dispatch.h>
#include <dlfcn.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#define __DISPATCH_INDIRECT__ 1
typedef dispatch_object_t dispatch_continuation_t;
#include "../../vendor/apple-libdispatch/private/introspection_private.h"

typedef void (*twq_dispatch_introspection_hooks_install_fn)(
		dispatch_introspection_hooks_t hooks);
typedef dispatch_introspection_queue_s
(*twq_dispatch_introspection_queue_get_info_fn)(dispatch_queue_t queue);

enum twq_root_kind {
	TWQ_ROOT_OTHER = 0,
	TWQ_ROOT_DEFAULT = 1,
	TWQ_ROOT_DEFAULT_OVERCOMMIT = 2,
};

struct twq_macos_dispatch_counter_state {
	_Atomic uint64_t root_push_total_default;
	_Atomic uint64_t root_push_empty_default;
	_Atomic uint64_t root_push_source_default;
	_Atomic uint64_t root_push_continuation_default;
	_Atomic uint64_t root_poke_slow_default;
	_Atomic uint64_t root_requested_threads_default;

	_Atomic uint64_t root_push_total_default_overcommit;
	_Atomic uint64_t root_push_empty_default_overcommit;
	_Atomic uint64_t root_push_mainq_default_overcommit;
	_Atomic uint64_t root_push_continuation_default_overcommit;
	_Atomic uint64_t root_poke_slow_default_overcommit;
	_Atomic uint64_t root_requested_threads_default_overcommit;

	_Atomic uint64_t pthread_workqueue_addthreads_calls;
	_Atomic uint64_t pthread_workqueue_addthreads_requested_threads;
};

static struct twq_macos_dispatch_counter_state twq_counter_state;
static dispatch_introspection_hooks_s twq_previous_hooks;
static twq_dispatch_introspection_hooks_install_fn twq_install_hooks;
static twq_dispatch_introspection_queue_get_info_fn twq_queue_get_info;
static _Atomic(uintptr_t) twq_default_root_ptr;
static _Atomic(uintptr_t) twq_default_overcommit_root_ptr;
static _Atomic uint64_t twq_default_root_depth;
static _Atomic uint64_t twq_default_overcommit_root_depth;
static bool twq_installed;
static bool twq_available;
static char twq_last_error[256];

static void
twq_set_error(const char *message)
{
	(void)snprintf(twq_last_error, sizeof(twq_last_error), "%s", message);
}

static void
twq_root_ptr_remember(_Atomic(uintptr_t) *slot, dispatch_queue_t queue)
{
	uintptr_t expected = 0;
	uintptr_t desired = (uintptr_t)queue;

	if (desired == 0)
		return;
	(void)atomic_compare_exchange_strong_explicit(slot, &expected, desired,
	    memory_order_relaxed, memory_order_relaxed);
}

static enum twq_root_kind
twq_classify_root_queue(dispatch_queue_t queue)
{
	const char *label;
	uintptr_t queue_ptr;

	if (queue == NULL)
		return (TWQ_ROOT_OTHER);

	queue_ptr = (uintptr_t)queue;
	if (queue_ptr == atomic_load_explicit(&twq_default_root_ptr, memory_order_relaxed))
		return (TWQ_ROOT_DEFAULT);
	if (queue_ptr == atomic_load_explicit(&twq_default_overcommit_root_ptr,
	    memory_order_relaxed))
		return (TWQ_ROOT_DEFAULT_OVERCOMMIT);

	label = dispatch_queue_get_label(queue);
	if (label == NULL || label[0] == '\0')
		return (TWQ_ROOT_OTHER);

	if (strcmp(label, "com.apple.root.default-qos") == 0) {
		twq_root_ptr_remember(&twq_default_root_ptr, queue);
		return (TWQ_ROOT_DEFAULT);
	}
	if (strstr(label, "com.apple.root.default-qos.overcommit") != NULL) {
		twq_root_ptr_remember(&twq_default_overcommit_root_ptr, queue);
		return (TWQ_ROOT_DEFAULT_OVERCOMMIT);
	}
	return (TWQ_ROOT_OTHER);
}

static void
twq_depth_decrement(_Atomic uint64_t *depth)
{
	uint64_t old_value;

	old_value = atomic_load_explicit(depth, memory_order_relaxed);
	while (old_value > 0) {
		if (atomic_compare_exchange_weak_explicit(depth, &old_value,
		    old_value - 1, memory_order_relaxed, memory_order_relaxed)) {
			return;
		}
	}
}

static bool
twq_item_is_main_queue(dispatch_introspection_queue_item_t item)
{
	return (item->type == dispatch_introspection_queue_item_type_queue &&
	    item->queue.main);
}

static bool
twq_item_is_source(dispatch_introspection_queue_item_t item)
{
	return (item->type == dispatch_introspection_queue_item_type_source);
}

static bool
twq_item_is_continuation(dispatch_introspection_queue_item_t item)
{
	return (item->type == dispatch_introspection_queue_item_type_block ||
	    item->type == dispatch_introspection_queue_item_type_function);
}

static void
twq_count_root_enqueue(dispatch_queue_t queue,
		dispatch_introspection_queue_item_t item)
{
	enum twq_root_kind root_kind;
	bool is_main_queue;
	bool is_source;
	bool is_continuation;
	uint64_t previous_depth;

	is_main_queue = twq_item_is_main_queue(item);
	is_source = twq_item_is_source(item);
	is_continuation = twq_item_is_continuation(item);

	if (is_main_queue) {
		twq_root_ptr_remember(&twq_default_overcommit_root_ptr, queue);
		root_kind = TWQ_ROOT_DEFAULT_OVERCOMMIT;
	} else {
		root_kind = twq_classify_root_queue(queue);
	}

	switch (root_kind) {
	case TWQ_ROOT_DEFAULT:
		previous_depth = atomic_fetch_add_explicit(&twq_default_root_depth, 1,
		    memory_order_relaxed);
		atomic_fetch_add_explicit(&twq_counter_state.root_push_total_default, 1,
		    memory_order_relaxed);
		if (previous_depth == 0) {
			atomic_fetch_add_explicit(&twq_counter_state.root_push_empty_default,
			    1, memory_order_relaxed);
		}
		if (is_source) {
			atomic_fetch_add_explicit(&twq_counter_state.root_push_source_default,
			    1, memory_order_relaxed);
		}
		if (is_continuation) {
			atomic_fetch_add_explicit(
			    &twq_counter_state.root_push_continuation_default, 1,
			    memory_order_relaxed);
		}
		break;
	case TWQ_ROOT_DEFAULT_OVERCOMMIT:
		previous_depth = atomic_fetch_add_explicit(
		    &twq_default_overcommit_root_depth, 1, memory_order_relaxed);
		atomic_fetch_add_explicit(
		    &twq_counter_state.root_push_total_default_overcommit, 1,
		    memory_order_relaxed);
		if (previous_depth == 0) {
			atomic_fetch_add_explicit(
			    &twq_counter_state.root_push_empty_default_overcommit, 1,
			    memory_order_relaxed);
		}
		if (is_main_queue) {
			atomic_fetch_add_explicit(
			    &twq_counter_state.root_push_mainq_default_overcommit, 1,
			    memory_order_relaxed);
		}
		if (is_continuation) {
			atomic_fetch_add_explicit(
			    &twq_counter_state.root_push_continuation_default_overcommit,
			    1, memory_order_relaxed);
		}
		break;
	case TWQ_ROOT_OTHER:
		break;
	}
}

static void
twq_dispatch_queue_item_enqueue(dispatch_queue_t queue,
		dispatch_introspection_queue_item_t item)
{
	twq_count_root_enqueue(queue, item);
	if (twq_previous_hooks.queue_item_enqueue != NULL) {
		twq_previous_hooks.queue_item_enqueue(queue, item);
	}
}

static void
twq_dispatch_queue_item_dequeue(dispatch_queue_t queue,
		dispatch_introspection_queue_item_t item)
{
	switch (twq_classify_root_queue(queue)) {
	case TWQ_ROOT_DEFAULT:
		twq_depth_decrement(&twq_default_root_depth);
		break;
	case TWQ_ROOT_DEFAULT_OVERCOMMIT:
		twq_depth_decrement(&twq_default_overcommit_root_depth);
		break;
	case TWQ_ROOT_OTHER:
		break;
	}
	if (twq_previous_hooks.queue_item_dequeue != NULL) {
		twq_previous_hooks.queue_item_dequeue(queue, item);
	}
}

static void
twq_dispatch_runtime_event(enum dispatch_introspection_runtime_event event,
		void *ptr, unsigned long long value)
{
	dispatch_queue_t queue;

	if (event != dispatch_introspection_runtime_event_worker_request) {
		if (twq_previous_hooks.runtime_event != NULL) {
			twq_previous_hooks.runtime_event(event, ptr, value);
		}
		return;
	}

	atomic_fetch_add_explicit(
	    &twq_counter_state.pthread_workqueue_addthreads_calls, 1,
	    memory_order_relaxed);
	atomic_fetch_add_explicit(
	    &twq_counter_state.pthread_workqueue_addthreads_requested_threads, value,
	    memory_order_relaxed);

	queue = (dispatch_queue_t)ptr;
	switch (twq_classify_root_queue(queue)) {
	case TWQ_ROOT_DEFAULT:
		atomic_fetch_add_explicit(&twq_counter_state.root_poke_slow_default, 1,
		    memory_order_relaxed);
		atomic_fetch_add_explicit(
		    &twq_counter_state.root_requested_threads_default, value,
		    memory_order_relaxed);
		break;
	case TWQ_ROOT_DEFAULT_OVERCOMMIT:
		atomic_fetch_add_explicit(
		    &twq_counter_state.root_poke_slow_default_overcommit, 1,
		    memory_order_relaxed);
		atomic_fetch_add_explicit(
		    &twq_counter_state.root_requested_threads_default_overcommit, value,
		    memory_order_relaxed);
		break;
	case TWQ_ROOT_OTHER:
		break;
	}

	if (twq_previous_hooks.runtime_event != NULL) {
		twq_previous_hooks.runtime_event(event, ptr, value);
	}
}

static void
twq_dispatch_seed_root_pointers(void)
{
	dispatch_queue_t default_root;
	dispatch_queue_t default_overcommit_root;
	dispatch_introspection_queue_s main_queue_info;

	default_root = dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0);
	twq_root_ptr_remember(&twq_default_root_ptr, default_root);
	if (twq_queue_get_info == NULL)
		return;

	main_queue_info = twq_queue_get_info(dispatch_get_main_queue());
	default_overcommit_root = main_queue_info.target_queue;
	twq_root_ptr_remember(&twq_default_overcommit_root_ptr,
	    default_overcommit_root);
}

int
twq_macos_dispatch_introspection_install(void)
{
	dispatch_introspection_hooks_s hooks = {0};

	if (twq_installed)
		return (twq_available ? 0 : -1);

	twq_install_hooks = (twq_dispatch_introspection_hooks_install_fn)dlsym(
	    RTLD_DEFAULT, "dispatch_introspection_hooks_install");
	twq_queue_get_info = (twq_dispatch_introspection_queue_get_info_fn)dlsym(
	    RTLD_DEFAULT, "dispatch_introspection_queue_get_info");
	if (twq_install_hooks == NULL) {
		twq_available = false;
		twq_set_error(
		    "dispatch introspection hooks unavailable; run with DYLD_LIBRARY_PATH=/usr/lib/system/introspection");
		twq_installed = true;
		return (-1);
	}

	hooks.queue_item_enqueue = twq_dispatch_queue_item_enqueue;
	hooks.queue_item_dequeue = twq_dispatch_queue_item_dequeue;
	hooks.runtime_event = twq_dispatch_runtime_event;
	twq_install_hooks(&hooks);
	twq_previous_hooks = hooks;
	twq_available = true;
	twq_installed = true;
	twq_last_error[0] = '\0';
	twq_dispatch_seed_root_pointers();
	twq_macos_dispatch_introspection_reset();
	return (0);
}

void
twq_macos_dispatch_introspection_reset(void)
{
	memset(&twq_counter_state, 0, sizeof(twq_counter_state));
	atomic_store_explicit(&twq_default_root_depth, 0, memory_order_relaxed);
	atomic_store_explicit(&twq_default_overcommit_root_depth, 0,
	    memory_order_relaxed);
}

int
twq_macos_dispatch_introspection_snapshot(
		struct twq_macos_dispatch_counters *out)
{
	if (out == NULL)
		return (-1);

	memset(out, 0, sizeof(*out));
	out->root_push_total_default = atomic_load_explicit(
	    &twq_counter_state.root_push_total_default, memory_order_relaxed);
	out->root_push_empty_default = atomic_load_explicit(
	    &twq_counter_state.root_push_empty_default, memory_order_relaxed);
	out->root_push_source_default = atomic_load_explicit(
	    &twq_counter_state.root_push_source_default, memory_order_relaxed);
	out->root_push_continuation_default = atomic_load_explicit(
	    &twq_counter_state.root_push_continuation_default, memory_order_relaxed);
	out->root_poke_slow_default = atomic_load_explicit(
	    &twq_counter_state.root_poke_slow_default, memory_order_relaxed);
	out->root_requested_threads_default = atomic_load_explicit(
	    &twq_counter_state.root_requested_threads_default, memory_order_relaxed);

	out->root_push_total_default_overcommit = atomic_load_explicit(
	    &twq_counter_state.root_push_total_default_overcommit,
	    memory_order_relaxed);
	out->root_push_empty_default_overcommit = atomic_load_explicit(
	    &twq_counter_state.root_push_empty_default_overcommit,
	    memory_order_relaxed);
	out->root_push_mainq_default_overcommit = atomic_load_explicit(
	    &twq_counter_state.root_push_mainq_default_overcommit,
	    memory_order_relaxed);
	out->root_push_continuation_default_overcommit = atomic_load_explicit(
	    &twq_counter_state.root_push_continuation_default_overcommit,
	    memory_order_relaxed);
	out->root_poke_slow_default_overcommit = atomic_load_explicit(
	    &twq_counter_state.root_poke_slow_default_overcommit,
	    memory_order_relaxed);
	out->root_requested_threads_default_overcommit = atomic_load_explicit(
	    &twq_counter_state.root_requested_threads_default_overcommit,
	    memory_order_relaxed);

	out->pthread_workqueue_addthreads_calls = atomic_load_explicit(
	    &twq_counter_state.pthread_workqueue_addthreads_calls,
	    memory_order_relaxed);
	out->pthread_workqueue_addthreads_requested_threads =
	    atomic_load_explicit(
	        &twq_counter_state.pthread_workqueue_addthreads_requested_threads,
	        memory_order_relaxed);
	return (0);
}

int
twq_macos_dispatch_introspection_available(void)
{
	return (twq_available ? 1 : 0);
}

const char *
twq_macos_dispatch_introspection_last_error(void)
{
	return (twq_last_error[0] != '\0' ? twq_last_error : NULL);
}
