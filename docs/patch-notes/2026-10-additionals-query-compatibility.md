# Additionals / RedmineUP query compatibility

## Failure and cause

With Additionals 4.5.0 and Redmine Contacts 4.5.0, opening `/issues` or
`/agile/board` can raise `SystemStackError (stack level too deep)`. The trace
alternates between Contacts' `add_available_filter` and Additionals'
`add_available_filter_with_additionals`.

Contacts prepends its query methods and calls `super`. Additionals aliases the
same methods when its concern is included. If Contacts has already been
prepended, Additionals' saved alias captures the Contacts method. The resulting
chain loops back into Contacts instead of reaching Redmine's query method.
The same conflict affects `add_filter`.

After correcting the filters, column rendering revealed another alias conflict:
`NoMethodError: super: no superclass method 'column_value'`, with Contacts,
Additionals' `column_value_with_category_link` and Checklists in the trace.
Additionals aliases the helper's method after Contacts has been prepended. This
captures the Contacts wrapper instead of the core helper implementation and
breaks the `super` chain during column rendering.

## Image correction

`config/build/additionals_query_prepend.patch` changes Additionals' query
instance methods to use `prepend` and replaces both alias wrappers with methods
that call `super`. Both plugins keep their Select2 initialization and filter
return behavior. The concern's attributes and class methods are retained.

The same patch also changes Additionals' query helper to prepend its
`column_value` wrapper and call `super` for ordinary columns. Category links
keep their existing guard and setting behavior; Contacts and Checklists keep
their own renderers. Both changes are required for the upgraded plugin set.
These are the only alias wrappers in Additionals 4.5.0's patch directory.

`install_core_plugins.sh` applies the patch immediately after cloning the pinned
Additionals 4.5.0 tag. A patch application failure stops the image build, making
source changes visible when upgrading Additionals again. There is no runtime
toggle for this source patch.

Build and deploy a new Taskman image to obtain the correction. Updating only the
runtime compatibility ConfigMap will not apply it. If a deployment mounts its
own `plugins/additionals` directory, refresh that directory from the patched
image or apply the same patch to its exact 4.5.0 source, then restart Redmine.
An ordinary container restart using the old image will retain the failure.

## Validation

- Patch application checked against the locally cloned Additionals 4.5.0 source;
  the user's clone was left unchanged.
- An isolated Ruby reproduction used the actual query wrapper bodies from
  Additionals 4.5.0 and Contacts 4.5.0, with database-backed Select2 hooks stubbed.
  Both original methods reproduced `SystemStackError`. The patched methods
  passed in both prepend orders, including missing filters: 4 tests,
  24 assertions, no failures.
- Rails regression coverage is added in
  `plugins/zzzz_eea_patches/test/unit/patches/query_filter_compat_test.rb` for
  `IssueQuery`, both Select2 hooks, unknown filters and `AgileQuery` initialization.
- An additional isolated reproduction used the actual column wrapper bodies
  from Additionals, Contacts and Checklists. The original helper reproduced the
  missing-superclass-method error. The corrected helper passed in all six
  prepend orders, covering core fallback, category links, missing categories,
  contact names/contact values and checklist rendering. Together with the filter
  reproduction: 11 tests, 111 assertions, no failures.
- `plugins/zzzz_eea_patches/test/unit/patches/query_columns_compat_test.rb` adds
  Rails coverage for core rendering, category helper/fallback, the disabled
  category-link setting, contact columns and checklist columns.
- Full Rails/container tests have not been run locally: Docker socket access is
  unavailable and the local Ruby environment does not contain Rails.

Before release, run the plugin regression suite in the CI image with the current
RedmineUP plugins installed. After deployment, check `/issues`, `/agile/board`,
user filters and contact filters, category links and checklist/contact columns.
Confirm that neither recursive query traces nor `column_value` errors appear in
the application log.
