config.logger = Logger.new(STDOUT)
config.logger.level = Logger::INFO

config.action_controller.perform_caching = true
config.cache_classes = true
# Rails 7.2+ can raise ArgumentError inside connection_pool when MemCacheStore
# is initialized with pooling enabled. Disable pooling to keep startup/migrations working.
config.cache_store = :mem_cache_store, 'memcached:11211', { pool: false }
config.action_controller.cache_store = :mem_cache_store, 'memcached:11211', { pool: false }
config.redmine_search_cache_store = :mem_cache_store, 'memcached:11211', { pool: false }
