#!/usr/sbin/dtrace -s
/*
 * Aggregate root queue push/poke/drain events by root queue pointer.
 */

#pragma D option quiet
#pragma D option dynvarsize=32m

dtrace:::BEGIN
{
	printf("collecting root queue summary...\n");
}

pid$target::_dispatch_twq_dtrace_root_queue_push_probe:entry
{
	@pushes[arg0] = count();
	@push_requested[arg0] = sum(arg3);
}

pid$target::_dispatch_twq_dtrace_root_queue_poke_probe:entry
{
	@pokes[arg0, arg3] = count();
	@poke_requested[arg0] = sum(arg1);
	@poke_requested_by_slow[arg0, arg3] = sum(arg1);
}

pid$target::_dispatch_twq_dtrace_continuation_pop_probe:entry
{
	@pops[arg1] = count();
}

dtrace:::END
{
	printa("pushes rq=%p count=%@d\n", @pushes);
	printa("push_requested rq=%p total=%@d\n", @push_requested);
	printa("pokes rq=%p slow=%d count=%@d\n", @pokes);
	printa("poke_requested rq=%p total=%@d\n", @poke_requested);
	printa("poke_requested_by_slow rq=%p slow=%d total=%@d\n",
	    @poke_requested_by_slow);
	printa("pops dq=%p count=%@d\n", @pops);
}
