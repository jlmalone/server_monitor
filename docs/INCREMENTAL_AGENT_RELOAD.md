# Incremental infrastructure configuration reload

The infrastructure supervisor reconciles schema-1 configurations by stable child/job ID.
Adding a tracker or another independent helper does not restart unrelated children,
resubmit unchanged scheduled jobs, or wait indefinitely for an existing queue drain.

An unchanged child command retains its PID. Policy-only changes update the live supervision
metadata. A removed or changed child retains its process handle until exit; a resistant child
receives the existing five-second termination deadline before a replacement can start. One
pending restart timer per ID prevents retry-timer multiplication, and removed IDs invalidate it.

Unchanged scheduled timers retain their cadence and last-run receipt. Changed/removed timers
stop future admissions while an already-running job drains under its existing deadline.
Timer-generation tokens reject callbacks from a cancelled timer even if the same ID is re-added.
Its admission fence and status remain visible, including when the job was removed from config.
An invalid configuration still fails closed for future work; it cannot erase an in-flight
job's ownership fence and allow a duplicate on recovery. Supervisor logs omit raw command argv.

Run `kotlin scripts/verify-agent-reload.main.kts` from the repository root for real-process
integration. It compiles the actual supervisor, starts isolated synthetic children/jobs,
and verifies stable PIDs, unchanged idle schedules, active-job ownership, selected removal,
SIGTERM-resistant replacement, invalid-config recovery, draining status and command-log privacy.
It never reads the operator's configuration or calls an external provider. Unit suites are deferred.

For that isolated run, `SERVERMONITOR_INFRASTRUCTURE_ROOT` must be an absolute directory and
selects its own config, logs and status files. Without it, existing production paths are unchanged.
No HOME or credential-store override is used.

The source fix does not hot-patch a running signed supervisor. The first installation/restart
still needs the normal shared-service delivery window, data/ownership checks and signed app.
Subsequent configuration edits gain incremental behavior after that version is running.
