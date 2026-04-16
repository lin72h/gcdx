#!/usr/sbin/dtrace -s
/*
 * M13 root push classifier for staged libdispatch.
 *
 * Reads the dispatch object's vtable from an explicit pre-publish probe shim.
 * Do not move this back into post-publish in-process code; that was the source
 * of the rc=139 crash.
 */

#pragma D option quiet
#pragma D option dynvarsize=32m

dtrace:::BEGIN
{
	printf("ts event tid rq obj vtable qos\n");
}

pid$target::_dispatch_twq_dtrace_root_queue_push_probe:entry
/arg1 != 0/
{
	this->vtable = *(uintptr_t *)copyin(arg1, sizeof(uintptr_t));
	printf("%d push_vtable %d %p %p %p %d\n",
	    timestamp, tid, arg0, arg1, this->vtable, arg3);
}

pid$target::_dispatch_twq_dtrace_root_queue_poke_probe:entry
/arg3 != 0/
{
	printf("%d poke_slow %d %p 0 0 %d\n",
	    timestamp, tid, arg0, arg1);
}

pid$target::_dispatch_twq_dtrace_continuation_pop_probe:entry
/arg0 != 0/
{
	this->vtable = *(uintptr_t *)copyin(arg0, sizeof(uintptr_t));
	printf("%d pop_vtable %d %p %p %p 0\n",
	    timestamp, tid, 0, arg0, this->vtable);
}

dtrace:::END
{
	printf("end\n");
}
