#!/usr/sbin/dtrace -s
/*
 * Pointer-only M13 libdispatch root trace.
 *
 * This uses explicit exported probe shims because FreeBSD's pid provider does
 * not reliably expose libdispatch's hidden/internal symbols. The push probe is
 * called before os_mpsc_push_list() publishes the item.
 */

#pragma D option quiet
#pragma D option dynvarsize=32m

dtrace:::BEGIN
{
	printf("ts event tid arg0 arg1 arg2 arg3\n");
}

pid$target::_dispatch_twq_dtrace_root_queue_push_probe:entry
{
	printf("%d root_queue_push %d %p %p %d 0\n",
	    timestamp, tid, arg0, arg1, arg3);
}

pid$target::_dispatch_twq_dtrace_root_queue_poke_probe:entry
{
	printf("%d root_queue_poke %d %p %d %d %d\n",
	    timestamp, tid, arg0, arg1, arg2, arg3);
}

pid$target::_dispatch_twq_dtrace_continuation_pop_probe:entry
{
	printf("%d continuation_pop %d %p %p %x %d\n",
	    timestamp, tid, arg0, arg1, arg2, arg3);
}

pid$target::_dispatch_twq_dtrace_queue_cleanup2_probe:entry
{
	printf("%d queue_cleanup2 %d %p %x %x %d\n",
	    timestamp, tid, arg0, arg1, arg2, arg3);
}

pid$target::_dispatch_twq_dtrace_async_redirect_probe:entry
{
	printf("%d async_redirect_invoke %d %p %p %p %d\n",
	    timestamp, tid, arg0, arg1, arg2, arg3);
}

dtrace:::END
{
	printf("end\n");
}
