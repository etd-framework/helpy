# Use this file to easily define all of your cron jobs.
#
# It's helpful, but not entirely necessary to understand cron before proceeding.
# http://en.wikipedia.org/wiki/Cron

# Example:
#
# set :output, "/path/to/my/cron_log.log"
#
# every 2.hours do
#   command "/usr/bin/some_great_command"
#   runner "MyModel.some_method"
#   rake "some:great:rake:task"
# end
#
# every 4.days do
#   runner "AnotherModel.prune_old_records"
# end

# Learn more: http://github.com/javan/whenever

env 'APP_DATABASE_PASSWORD', 'iwQnxramaPJ42vyJ@@'
env 'PATH', '/opt/plesk/ruby/2.4.3/bin:/var/www/vhosts/etd-solutions.com/.rbenv/shims:/usr/local/bin:/usr/bin:/usr/local/sbin:/usr/sbin:/usr/local/git/bin'

every 1.minute do
  rake "helpy:mailman"
end
