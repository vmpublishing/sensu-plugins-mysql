#!/usr/bin/env ruby
#
# MySQL Disk Usage Check
# ===
#
# Copyright 2011 Sonian, Inc <chefs@sonian.net>
#
# Released under the same terms as Sensu (the MIT license); see LICENSE
# for details.
#
# Check the size of the database and compare to crit and warn thresholds

require 'sensu-plugin/check/cli'
require 'mysql2'
require 'inifile'

class CheckMysqlDisk < Sensu::Plugin::Check::CLI

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

  option :size,
         long: '--size SIZE',
         description: 'Database size',
         required: true

  option :warn,
         short: '-w',
         long: '--warning VALUE',
         description: 'Warning threshold',
         default: '85'

  option :crit,
         short: '-c',
         long: '--critical VALUE',
         description: 'Critical threshold',
         default: '95'

  option :help,
         short: '-h',
         long: '--help',
         description: 'Check RDS disk usage',
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
    disk_size = config[:size].to_f
    critical_usage = config[:crit].to_f
    warning_usage = config[:warn].to_f
    total_size = 0.0

    results = @client.query <<-EOSQL
      SELECT table_schema,
      count(*) TABLES,
      concat(round(sum(table_rows)/1000000,2),'M') rows,
      round(sum(data_length)/(1024*1024*1024),2) DATA,
      round(sum(index_length)/(1024*1024*1024),2) idx,
      round(sum(data_length+index_length)/(1024*1024*1024),2) total_size,
      round(sum(index_length)/sum(data_length),2) idxfrac
      FROM information_schema.TABLES group by table_schema
    EOSQL

    if results.nil?
      critical "No connection to database"
    else
      results.each_hash do |row|
        total_size = total_size + row['total_size'].to_f
      end

      disk_use_percentage = total_size / disk_size * 100
      diskstr = "DB size: #{total_size}, disk use: #{disk_use_percentage}%"

      if disk_use_percentage > critical_usage
        critical "Database size exceeds critical threshold: #{diskstr}"
      elsif disk_use_percentage > warning_usage
        warning "Database size exceeds warning threshold: #{diskstr}"
      else
        ok diskstr
      end
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

