# Patch Notes (Detailed) — Runtime + Plugin Developer Update

Date: 2026-05-12  
Audience: Taskman maintainers, Helm operators, plugin developers (RedmineUP / custom plugin owners)

## 1) Why this note exists

This note documents a production-like performance investigation and the resulting patches so plugin maintainers can update upstream code safely.

It covers:

1. `redmine_contacts_helpdesk` sidebar count optimization (plugin view override)  
2. Activity feed author preload runtime patch (`TASKMAN_PATCH_ACTIVITY_AUTHOR_PRELOAD`)  
3. Helm/Kubernetes rollout behavior that affects how runtime patches are actually applied

---

## 2) Environment and observed issue

- Target endpoint with repeated timeout symptoms in test harness:  
  `/projects/perf_intensive_test/activity`
- Context: large project activity stream (~17k events in configured window).
- Initial harness behavior: 30s timeout (`curl 28`) with default test timeout.
- Extended direct request: returns `200` in ~30–32s.

Observed app log signature (before/after first remediation stage):

- `Completed 200 OK in ~30s`
- `~34k queries (~33.9k cached)`
- View time dominant

---

## 3) Patch A — Helpdesk sidebar counts (plugin-facing)

### 3.1 Affected plugin area

- Plugin: `redmine_contacts_helpdesk`
- View partial:
  `plugins/redmine_contacts_helpdesk/app/views/projects/_helpdesk_tickets.html.erb`

### 3.2 Root cause

The original partial used eager-loading relations for counting:

- `HelpdeskTicket.includes(:issue => [:project]).where(:projects => {:id => @project})`
- `Contact.includes(:tickets => :project).where(:projects => {:id => @project})`

On large projects this loads many rows/columns before counting, creating high memory and CPU pressure.

### 3.3 Implemented patch behavior

Replaced collection loading with indexed aggregate SQL counts:

- `ticket_count`: `HelpdeskTicket.joins(:issue).where(issues.project_id = @project.id).count`
- `customer_count`: `HelpdeskTicket.joins(:issue).where(issues.project_id = @project.id).where.not(contact_id: nil).distinct.count(:contact_id)`

### 3.4 Current implementation location in this repo

- Override file (active path in image):  
  `plugins/zzzz_eea_patches/app/views/projects/_helpdesk_tickets.html.erb`

This is a tactical override and should be upstreamed to plugin sources.

### 3.5 Expected impact

- Query path shifts from large result materialization to `COUNT` aggregates.
- Uses existing indexes:
  - `issues(project_id)`
  - `helpdesk_tickets(issue_id, contact_id)`
- Typical result: dramatic reduction in sidebar query cost.

### 3.6 Upstream recommendation for plugin maintainers

Please update plugin partial logic to compute counts via aggregate SQL (no eager-loading relation for counting).

Acceptance criteria for upstream plugin:

1. No `includes(...).count` style counting in this partial.
2. Use DB aggregate `COUNT`/`COUNT DISTINCT` query path.
3. Verify counts unchanged vs prior behavior.
4. Validate on large project dataset (10k+ tickets/events equivalent).

---

## 4) Patch B — Activity author preload runtime patch

### 4.1 Patch identity

- Runtime toggle: `TASKMAN_PATCH_ACTIVITY_AUTHOR_PRELOAD`
- Default: enabled (when env var missing)
- Source: `config/initializers/runtime_compat.rb`
- Scope: `Redmine::Activity::Fetcher#events`

### 4.2 Intended change

After `events` are fetched, events are grouped by class and `:author` association is preloaded in bulk via Rails preloader, to reduce per-event author lookups (`event_author` N+1 pattern).

### 4.3 Safety behavior

- HTML path only (skips `options[:limit]` path typically used by atom/limited fetch).
- Guarded by association existence checks.
- Rescue/fallback keeps original behavior if preload path errors.

### 4.4 Runtime validation in k8s

Boot log confirmation expected/observed:

- `[runtime_compat] patch=ACTIVITY_AUTHOR_PRELOAD enabled=true`

### 4.5 Result summary

- Endpoint no longer timed out under 30s harness limit in latest retest run.
- Latest measured latency for `/activity` dropped to ~12s (still high).
- Query count remained around ~34k with heavy cache hits.

Interpretation: this patch improves part of the cost profile but does not fully solve large activity page rendering cost for extreme event volumes.

---

## 5) Helm/Kubernetes operational note (critical)

### 5.1 What happened

In deployment, `runtime_compat.rb` can be mounted from ConfigMap (`runtime-compat-config`) using `subPath`.

Effect:

- Building/pulling a new image **does not** change effective runtime patch file if ConfigMap mount overlays that file.

### 5.2 Required rollout sequence when using ConfigMap override

1. Update ConfigMap data (`runtime-compat-config`) with new `runtime_compat.rb` content.
2. Restart/roll out deployment.
3. Confirm boot logs show expected patch flag line(s).

### 5.3 Documentation location

Helm release notes updated under `helm/README.md` (`Unreleased`) with this behavior.

---

## 6) Developer action checklist (plugin maintainers)

### redmine_contacts_helpdesk maintainers

- [ ] Replace sidebar counting logic with aggregate SQL counts.
- [ ] Add regression/performance test for large-project sidebar render.
- [ ] Verify count correctness parity.
- [ ] Release note: mention elimination of expensive eager-loading count pattern.

### Redmine activity/plugin integrators

- [ ] Review activity rendering path for large event windows (17k+ events).
- [ ] Consider explicit pagination/limit in HTML activity stream as follow-up.
- [ ] Keep preload optimizations guarded/toggled for safe rollback.

---

## 7) Follow-up recommendation (not applied yet)

To reduce `/activity` from ~12s to low seconds/sub-second territory on very large datasets, add an HTML event cap/pagination strategy in addition to author preload.

Rationale: current bottleneck remains largely view/render work for very large event collections.

---

## 8) Related files

- Runtime patch inventory: `docs/patches/PATCHES.md`
- Runtime patch source: `config/initializers/runtime_compat.rb`
- Helpdesk override: `plugins/zzzz_eea_patches/app/views/projects/_helpdesk_tickets.html.erb`
- Perf implementation notes: `performance_findings/FIX_IMPLEMENTATION.md`
- Helm release notes: `helm/README.md`
