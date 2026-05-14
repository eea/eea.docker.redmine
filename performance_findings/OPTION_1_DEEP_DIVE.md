# Option 1 Deep Dive: Custom Plugin

## What Is It?

A Redmine plugin that overrides specific plugin views by placing modified view files in the correct directory structure. Rails' view lookup mechanism finds your version first.

---

## How It Works (The Mechanics)

### Rails View Lookup Order

When Rails renders `projects/_helpdesk_tickets.html.erb`, it searches in this order:

1. **Your plugin:** `plugins/zzzz_eea_patches/app/views/projects/_helpdesk_tickets.html.erb`
2. **Original plugin:** `plugins/redmine_contacts_helpdesk/app/views/projects/_helpdesk_tickets.html.erb`
3. **Core Redmine:** `app/views/projects/_helpdesk_tickets.html.erb` (doesn't exist)

**Your file wins because it appears first in the lookup path.**

### How Redmine Registers Plugin Views

When Redmine boots:

```ruby
# Redmine's plugin loader does this:
Dir.glob(File.join(Rails.root, 'plugins/*/app/views')).each do |view_path|
  ActionController::Base.prepend_view_path(view_path)
end
```

This means all plugin view paths are prepended to Rails' view lookup.

**The key:** Plugin loading order determines precedence.

---

## Directory Structure

```
plugins/zzzz_eea_patches/           # Plugin root
├── app/
│   └── views/
│       └── projects/
│           └── _helpdesk_tickets.html.erb   # ← Your optimized view
├── config/
│   └── routes.rb                      # Optional: custom routes
├── init.rb                            # Plugin entry point
├── lib/
│   └── zzzz_eea_patches.rb         # Optional: Ruby patches
└── README.md                          # Documentation
```

### File Breakdown

#### 1. init.rb (The Entry Point)

```ruby
require 'redmine'

Redmine::Plugin.register :zzzz_eea_patches do
  name 'EEA Performance Patches'
  author 'EEA IT Team'
  description 'Performance optimizations for Redmine plugins'
  version '1.0.0'
  url 'https://github.com/eea/eea.docker.redmine'
  author_url 'https://www.eea.europa.eu'
  
  # Optional: specify requirements
  requires_redmine :version_or_higher => '5.0.0'
  
  # Optional: declare dependencies
  # This ensures our plugin loads AFTER the plugin we're patching
  requires_redmine_plugin :redmine_contacts_helpdesk, :version_or_higher => '4.0.0'
end

# Optional: Load additional Ruby patches
# require_dependency 'zzzz_eea_patches/helpdesk_patch'
```

**What this does:**
- Registers plugin with Redmine
- Adds your view paths to Rails lookup
- Controls loading order via dependencies

#### 2. The View File

```erb
<%# plugins/zzzz_eea_patches/app/views/projects/_helpdesk_tickets.html.erb %>
<%# 
  Optimized version of redmine_contacts_helpdesk view
  Replaces expensive includes() with indexed count queries
  Performance: <100ms vs >120s original
%>

<% if User.current.allowed_to?(:view_helpdesk_tickets, @project) %>
  <%# Optimized ticket count using existing indexes %>
  <% ticket_count = HelpdeskTicket.joins(:issue)
                                   .where(issues: { project_id: @project.id })
                                   .count %>
  
  <%# Optimized customer count using distinct %>
  <% customer_count = HelpdeskTicket.joins(:issue)
                                     .where(issues: { project_id: @project.id })
                                     .where.not(contact_id: nil)
                                     .distinct
                                     .count(:contact_id) %>
  
  <h3><%= l(:label_helpdesk_ticket_plural) %></h3>
  
  <p>
    <span class="icon icon-helpdesk">
      <%= sprite_icon('icon-helpdesk', 
            l(:text_helpdesk_ticket_count, :count => ticket_count), 
            plugin: :redmine_contacts_helpdesk) %>
    </span>
  </p>
  
  <p>
    <span class="icon icon-company-contact">
      <%= sprite_icon('user', 
            l(:text_helpdesk_customer_count, :count => customer_count)) %>
    </span>
  </p>
  
  <%# Commented out report link - kept for reference %>
  <p>
    <%# link_to(l(:label_report), 
          {:controller => "helpdesk_reports", 
           :action => "tickets_report", 
           :project_id => @project}) %>
  </p>
  
  <%= call_hook(:view_projects_show_helpdesk_sidebar_bottom, :project => @project) %>
<% end %>
```

**Key differences from original:**
- Replaces `if tickets = HelpdeskTicket.includes(...)` with direct count
- Replaces `customers = Contact.includes(...)` with distinct count on tickets
- Uses `joins` instead of `includes` (INNER vs LEFT OUTER JOIN)
- Stores counts in variables instead of loading all records

---

## Deployment Options

### Option A: Bake into Docker Image (Recommended)

**Dockerfile modification:**

```dockerfile
# After installing other plugins
COPY plugins/zzzz_eea_patches /usr/src/redmine/plugins/zzzz_eea_patches

# Ensure correct ownership
RUN chown -R redmine:redmine /usr/src/redmine/plugins/zzzz_eea_patches
```

**Pros:**
- ✅ Immutable infrastructure
- ✅ Version controlled with image
- ✅ No runtime dependencies
- ✅ Works offline

**Cons:**
- ❌ Requires image rebuild for updates
- ❌ Slightly larger image size

**Best for:** Production, CI/CD pipelines

### Option B: ConfigMap Mount (Kubernetes)

**ConfigMap creation:**

```yaml
# k8s/configmap-eea-patches.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: redmine-eea-patches
data:
  init.rb: |
    require 'redmine'
    Redmine::Plugin.register :zzzz_eea_patches do
      name 'EEA Performance Patches'
      author 'EEA'
      version '1.0.0'
    end
  
  _helpdesk_tickets.html.erb: |
    <% if User.current.allowed_to?(:view_helpdesk_tickets, @project) %>
      <% ticket_count = HelpdeskTicket.joins(:issue)... %>
      ...
```

**Deployment mount:**

```yaml
# In your deployment spec
volumeMounts:
  - name: eea-patches
    mountPath: /usr/src/redmine/plugins/zzzz_eea_patches
volumes:
  - name: eea-patches
    configMap:
      name: redmine-eea-patches
```

**Pros:**
- ✅ No image rebuild needed
- ✅ Update via kubectl apply
- ✅ GitOps friendly
- ✅ Quick iteration

**Cons:**
- ❌ Kubernetes-specific
- ❌ ConfigMap size limits (1MB)
- ❌ Slightly more complex

**Best for:** Development, rapid iteration, Kubernetes environments

### Option C: Init Container (Advanced)

```yaml
# In deployment spec
initContainers:
  - name: install-eea-patches
    image: busybox
    command:
      - sh
      - -c
      - |
        mkdir -p /plugins/zzzz_eea_patches/app/views/projects
        cat > /plugins/zzzz_eea_patches/init.rb << 'EOF'
        require 'redmine'
        Redmine::Plugin.register :zzzz_eea_patches do
          name 'EEA Patches'
          version '1.0.0'
        end
        EOF
        cat > /plugins/zzzz_eea_patches/app/views/projects/_helpdesk_tickets.html.erb << 'EOF'
        <%# Your view content here %>
        EOF
    volumeMounts:
      - name: plugins-volume
        mountPath: /plugins
```

**Pros:**
- ✅ Dynamic generation
- ✅ Can template values
- ✅ No ConfigMap needed

**Cons:**
- ❌ Complex
- ❌ Harder to debug

**Best for:** Dynamic environments, templating

### Option D: Runtime Git Clone (Development)

```bash
# In start_redmine.sh
if [ -n "${EEA_PATCHES_REPO}" ]; then
  git clone "${EEA_PATCHES_REPO}" /usr/src/redmine/plugins/zzzz_eea_patches
fi
```

**Pros:**
- ✅ Easy development workflow
- ✅ Always latest code

**Cons:**
- ❌ Requires network
- ❌ Not reproducible
- ❌ Security risk (supply chain)

**Best for:** Development only

---

## Maintenance

### Version Management

**Semantic versioning for your plugin:**

```ruby
# init.rb
version '1.0.0'
```

**Version bump rules:**
- **PATCH (1.0.1):** Bug fixes, query optimizations
- **MINOR (1.1.0):** New patches added
- **MAJOR (2.0.0):** Breaking changes (Redmine version compatibility)

### Testing

**Structure:**
```
plugins/zzzz_eea_patches/
├── test/
│   ├── test_helper.rb
│   └── integration/
│       └── helpdesk_performance_test.rb
└── spec/  # If using RSpec
    └── views/
        └── _helpdesk_tickets_spec.rb
```

**Example test:**

```ruby
# test/integration/helpdesk_performance_test.rb
require_relative '../test_helper'

class HelpdeskPerformanceTest < ActionDispatch::IntegrationTest
  fixtures :projects, :issues, :helpdesk_tickets

  def test_project_page_loads_quickly
    project = projects(:nanyt)
    
    # Benchmark the request
    time = Benchmark.measure do
      get project_path(project)
    end
    
    assert_response :success
    assert time.real < 5.0, "Page took #{time.real}s to load"
  end
  
  def test_ticket_count_is_accurate
    project = projects(:nanyt)
    expected_count = HelpdeskTicket.joins(:issue)
                                    .where(issues: { project_id: project.id })
                                    .count
    
    get project_path(project)
    
    assert_response :success
    assert_select 'span.icon-helpdesk', text: /#{expected_count}/
  end
end
```

### Updating

**When the original plugin updates:**

1. Check if the view file changed:
   ```bash
   diff plugins/redmine_contacts_helpdesk/app/views/projects/_helpdesk_tickets.html.erb \
        your-backup-of-original
   ```

2. If changed, update your version:
   - Review changes
   - Apply performance fix to new version
   - Test thoroughly
   - Bump plugin version

3. Deploy:
   ```bash
   # If using ConfigMap
   kubectl apply -f k8s/configmap-eea-patches.yaml
   kubectl rollout restart deployment/taskman-redmine -n taskman
   
   # If baked into image
   docker build -t eeacms/redmine:patched .
   kubectl set image deployment/taskman-redmine taskman-redmine=eeacms/redmine:patched
   ```

---

## Rollback

### Quick Rollback (Emergency)

```bash
# Option 1: Rename plugin (disables it)
kubectl exec taskman-redmine-dpl-<pod> -n taskman -c taskman-redmine -- \
  mv /usr/src/redmine/plugins/zzzz_eea_patches \
     /usr/src/redmine/plugins/zzzz_eea_patches.disabled

# Restart to clear view cache
kubectl rollout restart deployment/taskman-redmine -n taskman
```

### Proper Rollback (Version Control)

```bash
# Revert to previous ConfigMap
kubectl rollout undo configmap/redmine-eea-patches

# Or deploy previous version
git checkout v1.0.0 -- plugins/zzzz_eea_patches/
kubectl apply -f k8s/
```

---

## Pros and Cons Summary

### ✅ Pros

1. **Follows Conventions**
   - Standard Redmine plugin structure
   - Other Redmine developers understand it
   - Documentation exists

2. **Explicit and Clear**
   - Files are where you expect them
   - No magic or hidden behavior
   - Self-documenting structure

3. **Version Controlled**
   - Lives in git
   - Clear commit history
   - Code review friendly

4. **Testable**
   - Can write proper tests
   - CI/CD integration
   - Test isolation

5. **Reversible**
   - Disable = delete/rename directory
   - Clear on/off switch
   - No side effects

6. **Extensible**
   - Can add more patches later
   - Can patch controllers, models, helpers
   - Can add routes, assets, etc.

7. **Deployable**
   - Multiple deployment options
   - Works with Docker, Kubernetes, bare metal
   - Industry standard

### ❌ Cons

1. **Additional Component**
   - One more thing to maintain
   - Need to understand plugin lifecycle
   - Plugin loading order matters

2. **Redmine-Specific Knowledge**
   - Need to know Redmine plugin conventions
   - Must understand view lookup order
   - Redmine version compatibility

3. **Update Coordination**
   - Must track original plugin updates
   - Merge changes when upstream updates
   - Version compatibility testing

4. **Slight Complexity**
   - Directory structure to maintain
   - init.rb to write
   - Testing infrastructure

---

## Comparison with Other Options

| Aspect | Option 1 (Plugin) | Option 2 (Initializer) | Option 3 (DB View) |
|--------|------------------|----------------------|-------------------|
| **View Override** | ✅ Native support | ❌ Very hard | ❌ Separate solution needed |
| **Complexity** | Low-Medium | Low | Medium-High |
| **Maintainability** | ✅ High | Low | Medium |
| **Team Understanding** | ✅ Standard | Ruby expertise | DBA expertise |
| **Debugging** | ✅ Easy | Hard | Medium |
| **Testing** | ✅ Full support | Limited | Good |
| **Deployment** | ✅ Multiple options | Single file | Migrations + code |
| **Reversibility** | ✅ Delete directory | Delete file | Rollback migrations |

---

## When to Use Option 1

### ✅ Use It When:

- Changing view files (ERB templates)
- Need to override plugin behavior
- Want maintainable, professional solution
- Team knows Redmine conventions
- Long-term support required
- Multiple patches needed over time

### ❌ Don't Use It When:

- Just fixing a single method (use Option 2)
- Only optimizing complex aggregations (use Option 3)
- Need 5-minute emergency fix (use file copy)
- One-time temporary workaround
- Team has no Redmine knowledge

---

## Real-World Examples

### Example 1: EEA's Patch

**What:** Performance fix for helpdesk ticket counting  
**How:** Plugin with single view override  
**Deployment:** Baked into Docker image  
**Status:** Running in production

### Example 2: Theme Customization Plugin

**What:** Override Redmine views for branding  
**How:** Plugin with views/, assets/, and custom CSS  
**Deployment:** ConfigMap mount  
**Status:** Development environment

### Example 3: Integration Patches

**What:** Fix 5 different plugins for EEA-specific integrations  
**How:** Single plugin with views/, lib/, config/routes.rb  
**Deployment:** Git submodule  
**Status:** Production, maintained for 3+ years

---

## Getting Started Checklist

- [ ] Create plugin directory structure
- [ ] Write init.rb with metadata
- [ ] Copy and optimize view file
- [ ] Test locally with `rails server`
- [ ] Write automated tests
- [ ] Choose deployment strategy
- [ ] Add to CI/CD pipeline
- [ ] Document in team wiki
- [ ] Set up monitoring/alerts
- [ ] Plan for upstream updates

---

## Conclusion

Option 1 (Custom Plugin) is the **professional, maintainable, and correct** way to patch Redmine views. It requires slightly more setup than other options but pays off in:

- Long-term maintainability
- Team understanding
- Operational safety
- Extensibility for future patches

**It's the approach Redmine itself recommends for customizations.**
