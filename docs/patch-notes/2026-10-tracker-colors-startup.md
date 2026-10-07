# Tracker color startup correction

## Failure and correction

The `6.1.5-1.5` pod failed during production eager loading with
`NameError: uninitialized constant IssueTrackerColorPatch`. The two available
pods in Rancher still ran `6.1.5-1.3`; their readiness did not establish that
the new image had started successfully.

`lib/issue_tracker_color_patch.rb` registered a prepare callback without defining
its expected constant. Three additional root-level files defined `EeaPatches`
constants rather than the top-level constants implied by their paths.

- Define `IssueTrackerColorPatch` in its matching bootstrap file and retain its
  prepare callback.
- Move tracker color modules and the view hook into `lib/eea_patches/`, matching
  their existing namespace.
- Move both MiniProfiler modules into that directory and remove their top-level
  compatibility aliases. Their `defined?` guards can see an unresolved autoload
  as an existing constant and skip defining the alias.
- Update plugin initialization and test requires. The namespaced implementations
  and callback behavior are preserved.

Build and deploy a new image. If the plugin directory is mounted separately,
refresh its complete contents: retaining old root-level files retains invalid
loader paths. Updating only the runtime compatibility ConfigMap does not repair
these image-owned library files.

## Validation

`plugin_loading_test.rb` checks every plugin library file's Ruby autoload contract
in isolated subprocesses with Rails/Redmine dependencies stubbed. It covers
explicit loading before autoload registration and autoload before explicit
loading. Both cases reproduced the original failure and pass after correction.
The prepare callback runs twice to check that Issue and Gantt wrappers are not
duplicated. The first-boot regression described below brings this check to
3 tests, 9 assertions.

The standalone tracker color suite passes: 11 tests, 2,520 assertions. Rails
integration coverage now explicitly calls `Zeitwerk::Loader.eager_load_all`.
Full Rails/container tests have not run locally because Docker socket access is
unavailable. The standalone check does not replace a real production boot check.

Before release, run the Rails integration tests and, in a container configured
for a production-mode boot, run:

```sh
RAILS_ENV=production bundle exec rake zeitwerk:check
```

The tag-release pipeline skips regular branch test stages; creating a release
tag alone does not establish that these checks passed.

## First-boot badge correction

After resolving the constant paths, another initialization issue can leave
issue references as plain links. Redmine's plugin loader runs `init.rb` inside
its own `to_prepare` callback. Registering a new prepare callback there does not
ensure that the already compiled callback chain runs it on that first boot.
Production normally has no subsequent reload to install the patch.

`IssueTrackerColorPatch.apply!` now loads the dependencies and installs the color
wrappers immediately from plugin initialization. The prepare callback remains
for later reloads; its application is idempotent. A subprocess regression models
plugin initialization within the first prepare cycle, reproduces the missing
Issue/Gantt wrappers before correction, and passes afterward.

The same `Issue#css_classes` wrapper supplies generic color classes to reference
links in related issues, checklists, wikis and Gantt labels. Rails integration
coverage includes references with and without the tracker label. Shared CSS
selectors now cover link states explicitly and preserve closed-issue
strikethrough regardless of stylesheet ordering.

The palette generator is unchanged: new unconfigured trackers receive saturated,
stable colors, while valid explicit Agile colors retain priority. No separate
per-tracker badge palette or database backfill is introduced. The five existing
JavaScript checks pass against the Ruby palette; their Ruby require path is
updated for the namespace directory.

Deploy a new image and refresh the compiled assets so the updated stylesheet is
served. Verify reference badges on an issue page, a wiki and Gantt, including
closed references, hover/visited states and a new tracker. Browser DOM output
is still needed to confirm that a particular deployed page has the class,
stylesheet and generated palette; screenshots alone do not expose those values.

## Deployment configuration review

The failing pod also logged `CONTACT_GROUPS_IDS enabled=true`. The current
`config/initializers/runtime_compat.rb` neither applies that removed patch nor
logs its toggle. The pod therefore uses a different initializer. A stale mounted
ConfigMap is a likely cause, but the actual file and deployment mounts must be
inspected to confirm it. Inspect volume mounts and ConfigMap references in
Rancher or:

```sh
kubectl -n taskman get deployment taskman-redmine-dpl -o yaml
```

If a ConfigMap supplies `runtime_compat.rb`, update its key from the repository
version and roll out the corrected image. A `subPath` mount requires a new pod
to pick up the changed file. Remove the obsolete toggle as well; disabling it
alone does not update the stale initializer.

`TASKMAN_PATCH_BANNER_ENGINE_ROUTES=0` restores upstream Banner partials and
disables Taskman routing overrides. Review whether this is intentional when
testing banner actions inside plugin engines.

Missing `config/ai_helper/config.json` is nonfatal: AI Helper continues without
external MCP servers. An explicitly empty configuration is
`{"mcpServers": {}}` if no external servers are used. The RubyLLM legacy
`acts_as` warning is also nonfatal and separate from this loader failure.
Neither warning requires an AI Helper database migration to resolve this crash.
