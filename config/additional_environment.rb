   config.logger = Logger.new(STDOUT)
   config.logger.level = Logger::INFO

   config.action_controller.perform_caching  = true
   config.cache_classes = true
   config.cache_store = :mem_cache_store, "memcached:11211"
   config.action_controller.cache_store = :mem_cache_store, "memcached:11211"
   config.redmine_search_cache_store = :mem_cache_store, "memcached:11211"
