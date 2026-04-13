#include <dlfcn.h>
#include <pthread.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

extern "C" {

struct dispatch_queue_s;
typedef dispatch_queue_s *dispatch_queue_t;
typedef void (*dispatch_function_t)(void *);

struct swift_job;
struct twq_swift_serial_executor_ref {
  void *identity;
  uintptr_t implementation;
};

typedef void (*swift_task_enqueueGlobal_original)(swift_job *job);
typedef void (*swift_task_enqueueGlobalWithDelay_original)(
    unsigned long long delay, swift_job *job);
typedef void (*swift_task_enqueueGlobalWithDeadline_original)(
    long long sec, long long nsec, long long tsec, long long tnsec,
    int clock, swift_job *job);
typedef void (*swift_task_enqueueMainExecutor_original)(swift_job *job);
typedef void (*swift_job_run_original)(swift_job *job,
    twq_swift_serial_executor_ref executor);
typedef void (*dispatch_async_f_original)(dispatch_queue_t queue, void *context,
    dispatch_function_t work);

typedef void (*swift_task_enqueueGlobal_hook_t)(
    swift_job *job, swift_task_enqueueGlobal_original original);
typedef void (*swift_task_enqueueGlobalWithDelay_hook_t)(
    unsigned long long delay, swift_job *job,
    swift_task_enqueueGlobalWithDelay_original original);
typedef void (*swift_task_enqueueGlobalWithDeadline_hook_t)(
    long long sec, long long nsec, long long tsec, long long tnsec,
    int clock, swift_job *job,
    swift_task_enqueueGlobalWithDeadline_original original);
typedef void (*swift_task_enqueueMainExecutor_hook_t)(
    swift_job *job, swift_task_enqueueMainExecutor_original original);

extern swift_task_enqueueGlobal_hook_t swift_task_enqueueGlobal_hook;
extern swift_task_enqueueGlobalWithDelay_hook_t
    swift_task_enqueueGlobalWithDelay_hook;
extern swift_task_enqueueGlobalWithDeadline_hook_t
    swift_task_enqueueGlobalWithDeadline_hook;
extern swift_task_enqueueMainExecutor_hook_t
    swift_task_enqueueMainExecutor_hook;

extern uint64_t swift_task_getJobTaskId(swift_job *job);
}

static bool
twq_swift_hook_trace_enabled(void)
{
  static int enabled = -1;

  if (enabled == -1) {
    const char *value = getenv("TWQ_SWIFT_HOOK_TRACE");
    enabled = (value != nullptr && value[0] != '\0' && value[0] != '0') ? 1 : 0;
  }

  return enabled != 0;
}

static pthread_mutex_t twq_swift_known_jobs_lock = PTHREAD_MUTEX_INITIALIZER;
static void *twq_swift_known_jobs[256];
static uint64_t twq_swift_known_job_ids[256];
static size_t twq_swift_known_job_count;

static void
twq_swift_remember_job(swift_job *job)
{
  uint64_t task_id;

  if (job == nullptr) {
    return;
  }

  task_id = swift_task_getJobTaskId(job);

  pthread_mutex_lock(&twq_swift_known_jobs_lock);
  for (size_t index = 0; index < twq_swift_known_job_count; index++) {
    if (twq_swift_known_jobs[index] == job) {
      twq_swift_known_job_ids[index] = task_id;
      pthread_mutex_unlock(&twq_swift_known_jobs_lock);
      return;
    }
  }

  if (twq_swift_known_job_count < (sizeof(twq_swift_known_jobs) /
      sizeof(twq_swift_known_jobs[0]))) {
    twq_swift_known_jobs[twq_swift_known_job_count] = job;
    twq_swift_known_job_ids[twq_swift_known_job_count] = task_id;
    twq_swift_known_job_count++;
  }
  pthread_mutex_unlock(&twq_swift_known_jobs_lock);
}

static bool
twq_swift_lookup_job(void *context, uint64_t *task_id_out)
{
  bool found = false;

  pthread_mutex_lock(&twq_swift_known_jobs_lock);
  for (size_t index = 0; index < twq_swift_known_job_count; index++) {
    if (twq_swift_known_jobs[index] == context) {
      if (task_id_out != nullptr) {
        *task_id_out = twq_swift_known_job_ids[index];
      }
      found = true;
      break;
    }
  }
  pthread_mutex_unlock(&twq_swift_known_jobs_lock);

  return found;
}

static unsigned long long
twq_swift_hook_trace_now_usec(void)
{
  struct timespec ts;

  if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0) {
    return 0;
  }

  return (unsigned long long)ts.tv_sec * 1000000ull +
         (unsigned long long)(ts.tv_nsec / 1000ull);
}

static uint64_t
twq_swift_hook_trace_task_id(swift_job *job)
{
  if (job == nullptr) {
    return 0;
  }

  return swift_task_getJobTaskId(job);
}

static void
twq_swift_hook_trace_log(const char *event, const char *phase, swift_job *job,
    const char *extra_fmt = nullptr, ...)
{
  if (!twq_swift_hook_trace_enabled()) {
    return;
  }

  fprintf(stderr,
      "[swift-hook-trace] event=%s phase=%s ts_us=%llu tid=%llu job=%p task_id=%llu",
      event, phase, twq_swift_hook_trace_now_usec(),
      (unsigned long long)(uintptr_t)pthread_self(), (void *)job,
      (unsigned long long)twq_swift_hook_trace_task_id(job));

  if (extra_fmt != nullptr && extra_fmt[0] != '\0') {
    va_list ap;
    va_start(ap, extra_fmt);
    fputc(' ', stderr);
    vfprintf(stderr, extra_fmt, ap);
    va_end(ap);
  }

  fputc('\n', stderr);
  fflush(stderr);
}

static void
twq_swift_trace_enqueue_global(swift_job *job,
    swift_task_enqueueGlobal_original original)
{
  twq_swift_hook_trace_log("enqueueGlobal", "before", job);
  twq_swift_remember_job(job);
  original(job);
  twq_swift_hook_trace_log("enqueueGlobal", "after", job);
}

static void
twq_swift_trace_enqueue_global_with_delay(unsigned long long delay,
    swift_job *job, swift_task_enqueueGlobalWithDelay_original original)
{
  twq_swift_hook_trace_log("enqueueGlobalWithDelay", "before", job,
      "delay_ns=%llu", delay);
  original(delay, job);
  twq_swift_hook_trace_log("enqueueGlobalWithDelay", "after", job,
      "delay_ns=%llu", delay);
}

static void
twq_swift_trace_enqueue_global_with_deadline(long long sec, long long nsec,
    long long tsec, long long tnsec, int clock, swift_job *job,
    swift_task_enqueueGlobalWithDeadline_original original)
{
  twq_swift_hook_trace_log("enqueueGlobalWithDeadline", "before", job,
      "sec=%lld nsec=%lld tsec=%lld tnsec=%lld clock=%d",
      sec, nsec, tsec, tnsec, clock);
  original(sec, nsec, tsec, tnsec, clock, job);
  twq_swift_hook_trace_log("enqueueGlobalWithDeadline", "after", job,
      "sec=%lld nsec=%lld tsec=%lld tnsec=%lld clock=%d",
      sec, nsec, tsec, tnsec, clock);
}

static void
twq_swift_trace_enqueue_main(swift_job *job,
    swift_task_enqueueMainExecutor_original original)
{
  twq_swift_hook_trace_log("enqueueMainExecutor", "before", job);
  twq_swift_remember_job(job);
  original(job);
  twq_swift_hook_trace_log("enqueueMainExecutor", "after", job);
}

struct twq_swift_dispatch_async_wrapper {
  void *context;
  dispatch_function_t work;
  uint64_t task_id;
};

static dispatch_async_f_original
twq_dispatch_async_f_original_fn(void)
{
  static dispatch_async_f_original original =
      (dispatch_async_f_original)dlsym(RTLD_NEXT, "dispatch_async_f");
  return original;
}

static void
twq_swift_dispatch_async_wrapper_invoke(void *raw)
{
  twq_swift_dispatch_async_wrapper *wrapper =
      (twq_swift_dispatch_async_wrapper *)raw;

  twq_swift_hook_trace_log("dispatch_async_f", "invoke-before",
      (swift_job *)wrapper->context, "task_id=%llu wrapper=%p",
      (unsigned long long)wrapper->task_id, (void *)wrapper);
  wrapper->work(wrapper->context);
  twq_swift_hook_trace_log("dispatch_async_f", "invoke-after",
      (swift_job *)wrapper->context, "task_id=%llu wrapper=%p",
      (unsigned long long)wrapper->task_id, (void *)wrapper);
  free(wrapper);
}

extern "C" void
dispatch_async_f(dispatch_queue_t queue, void *context, dispatch_function_t work)
{
  dispatch_async_f_original original = twq_dispatch_async_f_original_fn();
  uint64_t task_id = 0;
  twq_swift_dispatch_async_wrapper *wrapper;

  if (original == nullptr) {
    return;
  }

  if (!twq_swift_hook_trace_enabled() ||
      !twq_swift_lookup_job(context, &task_id)) {
    original(queue, context, work);
    return;
  }

  twq_swift_hook_trace_log("dispatch_async_f", "queue",
      (swift_job *)context, "task_id=%llu queue=%p work=%p",
      (unsigned long long)task_id, (void *)queue, (void *)work);

  wrapper = (twq_swift_dispatch_async_wrapper *)malloc(sizeof(*wrapper));
  if (wrapper == nullptr) {
    twq_swift_hook_trace_log("dispatch_async_f", "oom",
        (swift_job *)context, "task_id=%llu queue=%p work=%p",
        (unsigned long long)task_id, (void *)queue, (void *)work);
    original(queue, context, work);
    return;
  }

  wrapper->context = context;
  wrapper->work = work;
  wrapper->task_id = task_id;
  twq_swift_hook_trace_log("dispatch_async_f", "queue-wrapper",
      (swift_job *)context, "task_id=%llu wrapper=%p queue=%p work=%p",
      (unsigned long long)task_id, (void *)wrapper, (void *)queue,
      (void *)work);
  original(queue, wrapper, twq_swift_dispatch_async_wrapper_invoke);
  twq_swift_hook_trace_log("dispatch_async_f", "queue-return",
      (swift_job *)context, "task_id=%llu wrapper=%p queue=%p work=%p",
      (unsigned long long)task_id, (void *)wrapper, (void *)queue,
      (void *)work);
}

static swift_job_run_original
twq_swift_job_run_original_fn(void)
{
  static swift_job_run_original original =
      (swift_job_run_original)dlsym(RTLD_NEXT, "swift_job_run");
  return original;
}

extern "C" void
swift_job_run(swift_job *job, twq_swift_serial_executor_ref executor)
{
  swift_job_run_original original = twq_swift_job_run_original_fn();

  if (original == nullptr) {
    twq_swift_hook_trace_log("jobRun", "missing-original", job,
        "executor_identity=%p executor_impl=0x%llx",
        executor.identity, (unsigned long long)executor.implementation);
    return;
  }

  if (!twq_swift_hook_trace_enabled()) {
    original(job, executor);
    return;
  }

  twq_swift_hook_trace_log("jobRun", "before", job,
      "executor_identity=%p executor_impl=0x%llx",
      executor.identity, (unsigned long long)executor.implementation);
  original(job, executor);
  twq_swift_hook_trace_log("jobRun", "after", job,
      "executor_identity=%p executor_impl=0x%llx",
      executor.identity, (unsigned long long)executor.implementation);
}

__attribute__((constructor))
static void
twq_swift_install_concurrency_hooks(void)
{
  if (!twq_swift_hook_trace_enabled()) {
    return;
  }

  swift_task_enqueueGlobal_hook = twq_swift_trace_enqueue_global;
  swift_task_enqueueGlobalWithDelay_hook =
      twq_swift_trace_enqueue_global_with_delay;
  swift_task_enqueueGlobalWithDeadline_hook =
      twq_swift_trace_enqueue_global_with_deadline;
  swift_task_enqueueMainExecutor_hook = twq_swift_trace_enqueue_main;

  twq_swift_hook_trace_log("install", "done", nullptr,
      "hooks=enqueueGlobal,enqueueGlobalWithDelay,enqueueGlobalWithDeadline,enqueueMainExecutor");
}
