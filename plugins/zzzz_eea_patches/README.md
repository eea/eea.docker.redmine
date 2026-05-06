# EEA Performance Patches Plugin

Redmine plugin providing performance optimizations and compatibility patches.

## Current Patches

### 1. Helpdesk Ticket Count Performance Fix

**File:** `app/views/projects/_helpdesk_tickets.html.erb`

**Problem:** The `redmine_contacts_helpdesk` plugin loads all 17K+ helpdesk tickets with expensive LEFT JOINs before counting them, causing page hangs (>120s timeout) for large private projects.

**Solution:** Replace eager-loading queries with indexed COUNT queries:

```ruby
# Before (Slow - >120s)
tickets = HelpdeskTicket.includes(:issue => [:project]).where(:projects => {:id => @project})
tickets.count

# After (Fast - <100ms)
HelpdeskTicket.joins(:issue).where(:issues => { :project_id => @project.id }).count
```

**Performance:**
- Query time: >120s → <100ms (>99.9% improvement)
- Data transfer: 1M+ values → 2 integers

**Affected Projects:**
- nanyt (EEA enquiries): 17,156 tickets, 11,244 customers

## Installation

### Option 1: Bake into Docker Image (Recommended for Production)

Add to Dockerfile:

```dockerfile
COPY plugins/redmine_eea_patches /usr/src/redmine/plugins/redmine_eea_patches
RUN chown -R redmine:redmine /usr/src/redmine/plugins/redmine_eea_patches
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
    mountPath: /usr/src/redmine/plugins/redmine_eea_patches
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

### When Upstream Plugin Updates

1. Check if `app/views/projects/_helpdesk_tickets.html.erb` changed:
   ```bash
   diff plugins/redmine_contacts_helpdesk/app/views/projects/_helpdesk_tickets.html.erb \
        plugins/redmine_eea_patches/app/views/projects/_helpdesk_tickets.html.erb.original
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
mv plugins/redmine_eea_patches plugins/redmine_eea_patches.disabled

# Restart Redmine
```

## Version History

- **1.0.0** - Initial release
  - Helpdesk ticket count performance fix

## License

Same as Redmine (GPL v2)

## Contact

EEA IT Team - https://www.eea.europa.eu
