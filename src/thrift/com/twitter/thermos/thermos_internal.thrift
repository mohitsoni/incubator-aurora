//  WorkflowTask(t): =>
//    - runner: pid [which after setsid is session leader]
//    - child:  pid [whose ppid is runner.pid]
//
//    => writes checkpoint_root/job_uid/tasks/{runner.pid}.ckpt
//       { { pid = pid, start_time = start_time }, ..., { stop_time = stop_time, return_code = return_code } }
//    => does does open/write/close for every write operation
//
//    death upon child finishing
//
//  Should the following happen
//
//    0) runner loses its underlying .ckpt:
//       means the parent somehow assumed it was lost or wants it to die, kill everything
//
//    1) runner dies but child lives
//       periodically poll for runner health
//       i) WorkflowRunner observes both runner.pid and child.pid -- if runner.pid goes away,
//          check for child.pid (do some accounting to make sure that pids are what we think
//          they are, obviously) -- kill child.pid, mark task LOST
//
//    2) child dies but runner lives
//       observed return_code
//       i) able to write before death
//          normal, write then exit [set to FINISHED/FAILED depending upon exit status]
//       ii) unable to write before death
//          WorkflowRunner observes both runner.pid and child.pid are missing,
//          marks task as LOST.
//
//    3) fork runner but never see {runner.pid}.ckpt -- kill {runner.pid} on a timeout.
//       => could there be a race condition where {runner.pid}.ckpt shows up after we've done a SIGKILL?
//
//  WorkflowTaskWatcher.add(t => runner.pid):
//    Observe {runner.pid}, and {child.pid} as known.
//    If at any point {runner.pid} goes away: slurp ckpt, if {child.pid} alive, kill & set LOST
//    If at any point {child.pid} goes away:
//       wait for {runner.pid} to die or 60 seconds, whichever comes first
//          slurp up {runner.pid}.ckpt
//          if conclusive, update state
//          if not, set LOST

namespace py thermos_thrift

enum WorkflowTaskRunState {
  // normal state
  WAITING   = 0   // blocked on execution dependencies or footprint restrictions
  FORKED    = 1   // starting, need to wait for signal from WorkflowTask that it's running
  RUNNING   = 2   // currently running
  FINISHED  = 3   // WorkflowTaskWatcher has finished and updated task state
  KILLED    = 4   // Killed by user action // not implemented yet

  // abnormal states
  FAILED    = 5   // returncode != 0
  LOST      = 6   // the runner_pid either died or some condition caused us to lose it.
}

// Sent as a stream of diffs
struct WorkflowTaskState {
  // Sequence number, must be monotonically increasing for all
  // WorkflowTaskState messages for a particular task across all runs.
  1: i64           seq

  // Task name
  3: string        task

  5: WorkflowTaskRunState run_state

  // WAITING -> FORKED
 10: i32           runner_pid
 11: double        fork_time

  // FORKED -> RUNNING
  6: double        start_time
  7: i32           pid

  // RUNNING -> {FINISHED, FAILED}
  8: double        stop_time
  9: i32           return_code

  // {FORKED, RUNNING} -> LOST nothing happens.  this TaskState ceases to exist.
  // Doesn't count against the run total.
}

// See lib/thermos/workflow/common/ckpt.py for the reconstruction logic.

enum WorkflowRunState {
  ACTIVE   = 0
  SUCCESS  = 1
  FAILED   = 2
}

enum WorkflowState {
  ACTIVE   = 0
  SUCCESS  = 1
  FAILED   = 2
}

struct WorkflowTaskHistory {
  1: WorkflowRunState state
  2: string task
  3: list<WorkflowTaskState> runs
}

// This is the first framed message in the Ckpt stream.  The rest are WorkflowTaskStates.
struct WorkflowRunnerHeader {
  1: string job_name
  2: i64    job_uid
  3: string workflow_name
  4: i32    workflow_replica
  5: i64    launch_time
  6: string hostname
}

struct WorkflowAllocatedPort {
  1: string port_name
  2: i32    port
}

struct WorkflowRunStateUpdate {
  1: string           task
  2: WorkflowRunState state
}

struct WorkflowStateUpdate {
  1: WorkflowState state
}

struct WorkflowRunnerCkpt {
  1: WorkflowRunnerHeader   runner_header
  2: WorkflowTaskState      task_state
  3: WorkflowAllocatedPort  allocated_port
  4: WorkflowRunStateUpdate history_state_update
  5: WorkflowStateUpdate    state_update
}

struct WorkflowRunnerState {
  1: WorkflowRunnerHeader header
  2: WorkflowState state
  3: map<string, WorkflowTaskHistory> tasks
  4: map<string, i32> ports
}