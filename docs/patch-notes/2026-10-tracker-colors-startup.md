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
duplicated. First-boot regressions, including Agile helper loading, bring this
check to 5 tests, 15 assertions.

The standalone tracker color suite passes: 13 tests, 6,659 assertions. Rails
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

At this stage the palette generator was unchanged: new unconfigured trackers
received saturated, stable colors, while valid explicit Agile colors retained
priority. The palette correction below supersedes that behavior. No separate
per-tracker badge palette or database backfill is introduced. The five existing
JavaScript checks pass against the Ruby palette; their Ruby require path is
updated for the namespace directory.

Deploy a new image and refresh the compiled assets so the updated stylesheet is
served. Verify reference badges on an issue page, a wiki and Gantt, including
closed references, hover/visited states and a new tracker. Browser DOM output
is still needed to confirm that a particular deployed page has the class,
stylesheet and generated palette; screenshots alone do not expose those values.

## Migration startup with Agile installed

The `6.1.5-1.7` migration hook failed while loading the Rails environment, before
database migrations executed, with `LoadError: cannot load such file --
agile_boards_helper`. Immediate badge installation exposed an unconditional
short-name require: plugin helper directories need not be on Ruby's `$LOAD_PATH`,
even when the helper constant has already been loaded by Agile.

The bootstrap now reuses `AgileBoardsHelper` when defined. Otherwise, it loads
`app/helpers/agile_boards_helper.rb` by absolute path from the registered Agile
plugin directory. Core issue/Gantt patches still install without Agile. Missing
files in an installed plugin continue to raise an error rather than silently
disabling board colors.

Two isolated first-boot regressions reproduce the original LoadError, then
verify successful, idempotent installation with a preloaded helper and with a
helper file outside `$LOAD_PATH`. These checks stub framework dependencies;
the full Rails migration/container checks remain required before release.

Rebuild the image and rerun the migration hook with the corrected plugin code.
Increasing Helm's timeout does not address this startup LoadError.

## Restore the original badge palette and white text

The working `6.1.5-1.7` badge patch revealed a visual regression compared with
the original Taskman theme. Agile's stored named colors took precedence over
the legacy palette: Bug became pure red, Feature pure blue, Task light green,
and Support yellow. Automatic foreground selection also switched several
badges to black text.

The shared resolver now prioritizes the known original tracker ID/name palette:
Bug `#e5123d`, Feature `#0065ff`, Task `#614ba6`, Support `#e67e22`, and the
other existing ID overrides. Explicit Agile colors remain supported for other
trackers. No database color records are changed.

Generated colors retain deterministic hue spacing but use a more tempered
range. Backgrounds are darkened when necessary to provide at least 4.5:1
contrast against white text, with no automatic gray/white fallback. Original
palette colors and explicit user colors remain exact; their contrast is not
covered by the generated-color guarantee.

Server-rendered CSS variables and the AJAX/ActionCable observer now always
use white foregrounds for badges and hover states. The shared palette still
drives issue links, list indicators, HTML Gantt, Agile tracker-mode cards and
tracker charts. Pale card backgrounds and Gantt progress/late overlays remain.

Standalone regressions cover conflicting stored Agile colors for the original
trackers, stable tempered defaults, white badge/hover text, and contrast across
1,000 generated tracker IDs. All five JavaScript checks also verify agreement
with server-rendered rules. Rebuild the image and refresh compiled assets;
verify the deployed badge appearance against the reference screenshot.

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
