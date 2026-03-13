log_level_name = ENV.fetch('RAILS_LOG_LEVEL', 'info').upcase
log_level = Logger.const_get(log_level_name)
cache_servers = ENV.fetch('MEMCACHE_SERVERS', 'memcached:11211').split(',')
cache_options = {
  pool: false,
  namespace: ENV.fetch('MEMCACHE_NAMESPACE', 'redmine'),
  compress: true,
  expires_in: ENV.fetch('MEMCACHE_EXPIRES_IN', '3600').to_i
}

asset_warning_filters = [
  /MCP config file not found:/,
  /Unable to resolve .* for missing asset /,
  /Removed sourceMappingURL comment for missing asset /
]
log_formatter = proc do |severity, timestamp, progname, msg|
  message = msg.to_s
  if severity == 'WARN' && asset_warning_filters.any? { |pattern| pattern.match?(message) }
    ''
  else
    prog = progname ? " #{progname}" : ''
    "#{severity[0]}, [#{timestamp.utc.strftime('%Y-%m-%dT%H:%M:%S.%6NZ')} ##{Process.pid}] #{severity} --#{prog}: #{message}\n"
  end
end

stdout_logger = ActiveSupport::Logger.new(STDOUT)
stdout_logger.level = log_level
stdout_logger.formatter = log_formatter

stderr_logger = ActiveSupport::Logger.new(STDERR)
stderr_logger.level = [log_level, Logger::ERROR].max
stderr_logger.formatter = log_formatter

config.logger = ActiveSupport::BroadcastLogger.new(stdout_logger, stderr_logger)
config.log_level = log_level_name.downcase
config.active_support.report_deprecations = false if config.respond_to?(:active_support)

Thread.abort_on_exception = false
Thread.report_on_exception = true if Thread.respond_to?(:report_on_exception=)

if defined?(Rails) && Rails.respond_to?(:error)
  rails_stderr_subscriber = Object.new
  rails_stderr_subscriber.define_singleton_method(:report) do |error, handled:, severity:, context:, source:|
    next if handled

    STDERR.puts("[rails-error] source=#{source} severity=#{severity} #{error.class}: #{error.message}")
    Array(error.backtrace).first(10).each { |line| STDERR.puts(line) }
  rescue StandardError => subscribe_error
    STDERR.puts("[rails-error] subscriber-failure #{subscribe_error.class}: #{subscribe_error.message}")
  end

  Rails.error.subscribe(rails_stderr_subscriber)
end

config.action_controller.perform_caching = true
config.cache_classes = true
config.eager_load = true
config.action_view.cache_template_loading = true
config.active_record.default_timezone = :utc if config.respond_to?(:active_record)

# Keep job backend explicit and configurable across web/cron containers.
if config.respond_to?(:active_job)
  adapter_name = ENV.fetch('ACTIVE_JOB_QUEUE_ADAPTER', 'solid_queue')
  config.active_job.queue_adapter = adapter_name.to_sym
end

# Rails 7.2+ can raise ArgumentError inside connection_pool when MemCacheStore
# is initialized with pooling enabled. Disable pooling to keep startup/migrations working.
config.cache_store = :mem_cache_store, cache_servers, cache_options
config.action_controller.cache_store = :mem_cache_store, cache_servers, cache_options
config.redmine_search_cache_store = :mem_cache_store, cache_servers, cache_options

if ENV['AGILE_BOARD_PROFILE'] == '1'
  ActiveSupport::Notifications.subscribe('process_action.action_controller') do |_name, _start_t, _finish_t, _id, payload|
    path = payload[:path].to_s
    next unless path.include?('/agile/board')

    controller = payload[:controller].to_s
    action = payload[:action].to_s
    status = payload[:status]
    total_ms = payload[:duration].to_f
    view_ms = payload[:view_runtime].to_f
    db_ms = payload[:db_runtime].to_f

    Rails.logger.warn(
      "[agile-board-profile] controller=#{controller} action=#{action} path=#{path} " \
      "status=#{status} total_ms=#{total_ms.round(1)} db_ms=#{db_ms.round(1)} view_ms=#{view_ms.round(1)}"
    )
  end
end
