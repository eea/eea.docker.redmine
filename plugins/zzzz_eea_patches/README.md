# Taskman Plugin Patches (`zzzz_eea_patches`)

Redmine plugin providing performance optimizations and compatibility patches.

## Patch Documentation

Single source of truth for all patches (full standardized format with code blocks):

- `docs/patches/CURRENT_PATCHES.md`

## Installation

### Option 1: Bake into Docker Image (Recommended for Production)

Add to Dockerfile:

```dockerfile
COPY plugins/zzzz_eea_patches /usr/src/redmine/plugins/zzzz_eea_patches
RUN chown -R redmine:redmine /usr/src/redmine/plugins/zzzz_eea_patches
```

### Option 2: Kubernetes ConfigMap (Development)

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: redmine-eea-patches
data:
  # Copy content of init.rb and view file here
```

Mount in deployment:

```yaml
volumeMounts:
  - name: eea-patches
    mountPath: /usr/src/redmine/plugins/zzzz_eea_patches
volumes:
  - name: eea-patches
    configMap:
      name: redmine-eea-patches
```

## Testing

### Automatic tracker colors (#309004)

`lib/eea_patches/tracker_colors.rb` resolves a tracker color in this order:

1. Valid explicit Agile color (named colors or HEX).
2. Existing Taskman ID/name palette for the original trackers 1–13.
3. A saturated, deterministic color derived from the tracker ID.

Defaults apply to existing unconfigured trackers and newly created trackers,
without database writes or migrations. Renaming a new tracker keeps its color.
Explicit gray colors remain supported; automatic colors never use gray/white.
The generated spectrum is finite: very large tracker sets can have similar hues.

Issue badges/list indicators, HTML Gantt bars, Agile cards in tracker mode,
cycle-time charts and tracker cumulative-flow charts share this resolver.
Card backgrounds use a pale tint and a solid tracker stripe. Gantt done/late
fills retain their existing meaning, with a tracker-colored stripe.
Other Agile coloring modes and the synthetic mixed-tracker chart series keep
their existing behavior. Gantt PDF/PNG exports retain Redmine's export colors.

The head hook emits CSS variables and loads plugin assets. The JS observer
adds rules for trackers introduced through AJAX/ActionCable after page load.
Patches are installed immediately during plugin initialization and idempotently
reapplied through Rails `to_prepare`. Redmine itself loads plugin initializers
inside a prepare callback; deferring installation to a newly registered callback
can leave the first production boot without the issue color classes.
When Agile is installed, initialization reuses its loaded board helper or loads
it from the registered plugin directory by absolute path. This also supports
migration jobs where plugin helper directories are outside Ruby's `$LOAD_PATH`.

Badge selectors apply to issue reference links throughout Redmine (including
wikis, checklists, related issues and Gantt labels). Visited/hovered links retain
the badge, and closed links retain their strikethrough. They all use the shared
generic palette rather than a separate set of per-name colors.

Local checks without Rails:

```bash
ruby plugins/zzzz_eea_patches/test/unit/tracker_colors_test.rb
ruby plugins/zzzz_eea_patches/test/unit/plugin_loading_test.rb
node --test plugins/zzzz_eea_patches/test/tracker_colors_assets_test.js
```

In a Redmine test instance with Agile enabled:

```bash
RAILS_ENV=test bundle exec rake redmine:plugins:test PLUGIN=zzzz_eea_patches
```

Deployment requires rebuilding the image for the plugin code/assets, refreshing
the A1 override (`ADDONS_SYNC_SKIP_IF_PRESENT=0` during addon sync), and asset
precompilation. No tracker color backfill is needed. Verify Stream and a new
tracker in lists, Gantt, Kanban and charts, including a card update without
reloading the board. Configured Agile colors take priority over old A1 colors
when those two sources previously disagreed.

After deployment:

1. Access `/projects/nanyt` as user with limited permissions
2. Page should load in <5 seconds
3. Verify counts display correctly:
   - Tickets: 17,156
   - Customers: 11,244

## Maintenance

Additional maintainer references:

- `CHANGES.md` — side-by-side original vs optimized file diff and SQL impact
- `PLUGIN_UPGRADE_GUIDE.md` — upgrade workflow and compatibility strategy
- `LEGACY_PATCHES.md` — legacy/ad-hoc patch notes and migration guidance

### When Upstream Plugin Updates

1. Check if `app/views/projects/_helpdesk_tickets.html.erb` changed:
   ```bash
   diff plugins/redmine_contacts_helpdesk/app/views/projects/_helpdesk_tickets.html.erb \
        plugins/zzzz_eea_patches/app/views/projects/_helpdesk_tickets.html.erb.original
   ```

2. If changed:
   - Extract new original file
   - Re-apply performance optimizations
   - Update version number in `init.rb`
   - Test thoroughly
   - Deploy

### Rollback

To disable patches:

```bash
# Rename plugin directory
mv plugins/zzzz_eea_patches plugins/zzzz_eea_patches.disabled

# Restart Redmine
```

## Version History

- **1.0.0** - Initial release
  - Helpdesk ticket count performance fix

## License

Same as Redmine (GPL v2)

## Contact

EEA IT Team - https://www.eea.europa.eu
