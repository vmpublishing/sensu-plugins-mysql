#!/usr/bin/env ruby
#
#   check-mysql-threads.rb
#
# DESCRIPTION:
#   MySQL Threads Health plugin
#   This plugin evaluates the number of MySQL running threads and warns you according to specified limits
#
# OUTPUT:
#   plain text
#
# PLATFORMS:
#   All
#
# DEPENDENCIES:
#   gem: sensu-plugin
#
# USAGE:
#   check-mysql-threads.rb -w [threshold] -c [threshold]
#
# NOTES:
#
# LICENSE:
#   Author: Guillaume Lefranc <guillaume@mariadb.com>
#   Released under the same terms as Sensu (the MIT license); see LICENSE
#   for details.
#

require 'sensu-plugin/check/cli'
require 'mysql2'
require 'inifile'

class CheckMysqlThreads < Sensu::Plugin::Check::CLI

  option :hostname,
         description: 'Hostname to login to',
         short: '-h HOST',
         long: '--hostname HOST'

  option :user,
         description: 'MySQL User',
         short: '-u USER',
         long: '--user USER'

  option :password,
         description: 'MySQL Password',
         short: '-p PASS',
         long: '--password PASS'

  option :port,
         description: 'Port to connect to',
         short: '-P PORT',
         long: '--port PORT',
         default: '3306'

  option :database,
         description: 'Database schema to connect to',
         short: '-d DATABASE',
         long: '--database DATABASE'

  option :ini,
         description: 'My.cnf ini file',
         short: '-i',
         long: '--ini VALUE'

  option :socket,
         description: 'Socket to use',
         short: '-s SOCKET',
         long: '--socket SOCKET'

  option :maxwarn,
         description: "Number of running threads upon which we'll issue a warning",
         short: '-w NUMBER',
         long: '--warnnum NUMBER',
         default: 20

  option :maxcrit,
         description: "Number of running threads upon which we'll issue an alert",
         short: '-c NUMBER',
         long: '--critnum NUMBER',
         default: 25


  def connect
    section = {}
    if config[:ini]
      ini = IniFile.load(config[:ini])
      section = ini['client']
    end

    @connection_info = {
      host:       section[    'host'] || config[:hostname],
      username:   section[    'user'] || config[    :user],
      password:   section['password'] || config[:password],
      database:   section['database'] || config[:database],
      port:       section[    'port'] || config[    :port],
      socket:     section[  'socket'] || config[  :socket],
    }
    @client = Mysql2::Client.new(@connection_info)
  end


  def run_test
    threads_running = @client.query("SHOW GLOBAL STATUS LIKE 'Threads_running'").first.values.first.to_i

    if config[:maxcrit].to_i <= threads_running
      critical "MySQL currently running threads: #{run_thr}"
    elsif config[:maxwarn].to_i <= threads_running
      warning "MySQL currently running threads: #{run_thr}"
    else
      ok "Currently running threads are under limit in MySQL: #{threads_running}"
    end
  end


  def run
    connect
    run_test
  rescue Mysql2::Error => e
    critical e.message
  rescue => e
    critical "UNKNOWN: #{e.message}\n\n#{e.backtrace.join('\n')}"
  ensure
    @client.close if @client
  end

end

