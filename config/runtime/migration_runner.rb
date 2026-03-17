#!/usr/bin/env ruby
# frozen_string_literal: true

require "open3"

TASKS = {
  "db" => "db:migrate",
  "plugins" => "redmine:plugins:migrate"
}.freeze

task_key = ARGV.shift
task_name = TASKS[task_key]
unless task_name
  warn "usage: #{File.basename(__FILE__)} [db|plugins]"
  exit 1
end

retries = Integer(ENV.fetch("MIGRATION_RETRIES", "30"))
delay = Integer(ENV.fetch("MIGRATION_RETRY_DELAY", "2"))

def run_task(task_name)
  cmd = ["/docker-entrypoint.sh", "rake", task_name]
  Open3.capture2e(*cmd)
end

def lock_error?(output)
  output.include?("ConcurrentMigrationError")
end

start = Time.now
puts "[migration_runner] phase=#{task_name} status=start"

1.upto(retries) do |attempt|
  output, status = run_task(task_name)
  print(output)

  if status.success?
    puts "[migration_runner] phase=#{task_name} status=ok attempts=#{attempt} duration=#{(Time.now - start).round(2)}s"
    exit 0
  end

  unless lock_error?(output)
    puts "[migration_runner] phase=#{task_name} status=failed reason=non_retryable attempts=#{attempt}"
    exit 1
  end

  puts "[migration_runner] phase=#{task_name} status=retry reason=lock attempts=#{attempt}/#{retries} sleep=#{delay}s"
  sleep(delay)
end

puts "[migration_runner] phase=#{task_name} status=failed reason=exhausted_retries attempts=#{retries}"
exit 1
