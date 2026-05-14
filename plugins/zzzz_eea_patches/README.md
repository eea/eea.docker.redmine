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
