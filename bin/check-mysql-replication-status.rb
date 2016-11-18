#!/usr/bin/env ruby
#
# MySQL Replication Status (modded from disk)
# ===
#
# Copyright 2011 Sonian, Inc <chefs@sonian.net>
# Updated by Oluwaseun Obajobi 2014 to accept ini argument
#
# Released under the same terms as Sensu (the MIT license); see LICENSE
# for details.
#
# USING INI ARGUMENT
# This was implemented to load mysql credentials without parsing the username/password.
# The ini file should be readable by the sensu user/group.
# Ref: http://eric.lubow.org/2009/ruby/parsing-ini-files-with-ruby/
#
#   EXAMPLE
#     mysql-alive.rb -h db01 --ini '/etc/sensu/my.cnf'
#
#   MY.CNF INI FORMAT
#   [client]
#   user=sensu
#   password="abcd1234"
#

require 'sensu-plugin/check/cli'
require 'mysql2'
require 'inifile'

class CheckMysqlReplicationStatus < Sensu::Plugin::Check::CLI

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

  option :warn,
         short: '-w',
         long: '--warning=VALUE',
         description: 'Warning threshold for replication lag',
         default: 900,
         # #YELLOW
         proc: lambda { |s| s.to_i } # rubocop:disable Lambda

  option :crit,
         short: '-c',
         long: '--critical=VALUE',
         description: 'Critical threshold for replication lag',
         default: 1800,
         # #YELLOW
         proc: lambda { |s| s.to_i } # rubocop:disable Lambda

  option :help,
         short: '-h',
         long: '--help',
         description: 'Check MySQL replication status',
         on: :tail,
         boolean: true,
         show_options: true,
         exit: 0


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
    results = @client.query 'show slave status'

    unless results.nil?
      results.each do |row|
        warn "couldn't detect replication status" unless
          %w(Slave_IO_State Slave_IO_Running Slave_SQL_Running Last_IO_Error Last_SQL_Error Seconds_Behind_Master).all? do |key|
            row.key? key
          end

        slave_running = %w(Slave_IO_Running Slave_SQL_Running).all? do |key|
          row[key] =~ /Yes/
        end

        output = 'Slave not running!'
        output += ' STATES:'
        output += " Slave_IO_Running=#{row['Slave_IO_Running']}"
        output += ", Slave_SQL_Running=#{row['Slave_SQL_Running']}"
        output += ", LAST ERROR: #{row['Last_SQL_Error']}"

        critical output unless slave_running

        replication_delay = row['Seconds_Behind_Master'].to_i

        message = "replication delayed by #{replication_delay}"

        if replication_delay > config[:warn] &&
           replication_delay <= config[:crit]
          warning message
        elsif replication_delay >= config[:crit]
          critical message
        else
          ok "slave running: #{slave_running}, #{message}"
        end
      end
      ok 'show slave status was nil. This server is not a slave.'
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

