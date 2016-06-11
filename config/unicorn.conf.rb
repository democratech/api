require 'bundler/setup'

# This unicorn config file has been inspired by :
# http://shapeshed.com/managing-unicorn-workers-with-monit/
# http://nebulab.it/blog/monitoring-unicorn-with-monit
# For complete documentation, see http://unicorn.bogomips.org/Unicorn/Configurator.html
APP_ROOT = File.expand_path(File.dirname(File.dirname(__FILE__)))

# Use at least one worker per core if you're on a dedicated server,
# more will usually help for _short_ waits on databases/caches.
worker_processes 30

# Help ensure your application will always spawn in the symlinked
# "current" directory that Capistrano sets up.
working_directory APP_ROOT # available in 0.94.0+

# listen on both a Unix domain socket and a TCP port,
# we use a shorter backlog for quicker failover when busy
listen 9292, :tcp_nopush => true

# nuke workers after 30 seconds instead of 60 seconds (the default)
timeout 30

# Whether the app should be pre-loaded
preload_app true

# feel free to point this anywhere accessible on the filesystem
if ENV['RACK_ENV']=='production' then
	stderr_path "/var/log/unicorn/api.democratech.co.err.log"
	stdout_path "/var/log/unicorn/api.democratech.co.log"
	user 'www-data', 'www-data'
end
pid "%s/pid/pid" % [APP_ROOT]

# The user/group to run unicorn as

if GC.respond_to?(:copy_on_write_friendly=)
  GC.copy_on_write_friendly = true
end

before_exec do |server|
  ENV['BUNDLE_GEMFILE'] = File.expand_path('../Gemfile', File.dirname(__FILE__))
end

before_fork do |server, worker|
  defined?(ActiveRecord::Base) && ActiveRecord::Base.connection.disconnect!
  old_pid = "/var/run/unicorn/api.democratech.co/pid.oldbin"
  if File.exists?(old_pid) && server.pid != old_pid
    begin
      Process.kill('QUIT', File.read(old_pid).to_i)
    rescue Errno::ENOENT, Errno::ESRCH
      # someone else did our job for us
    end
  end
end

# What to do after we fork a worker
after_fork do |server, worker|
  defined?(ActiveRecord::Base) && ActiveRecord::Base.establish_connection
  # Create worker pids too
  child_pid = server.config[:pid].sub(/pid$/, "worker.#{worker.nr}.pid")
  system("echo #{Process.pid} > #{child_pid}")
end
