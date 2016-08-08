#!/usr/bin/env ruby
#
# MySQL Health Plugin
# ===
#
# This plugin counts the maximum connections your MySQL has reached and warns you according to specified limits
#
# Copyright 2012 Panagiotis Papadomitsos <pj@ezgr.net>
#
# Released under the same terms as Sensu (the MIT license); see LICENSE
# for details.

require 'sensu-plugin/check/cli'
require 'mysql2'
require 'inifile'

class CheckMySQLHealth < Sensu::Plugin::Check::CLI

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
         long: '--database DATABASE',
         default: 'test'

  option :ini,
         description: 'My.cnf ini file',
         short: '-i',
         long: '--ini VALUE'

  option :socket,
         description: 'Socket to use',
         short: '-s SOCKET',
         long: '--socket SOCKET'

  option :maxwarn,
         description: "Number of connections upon which we'll issue a warning",
         short: '-w NUMBER',
         long: '--warnnum NUMBER',
         default: 100

  option :maxcrit,
         description: "Number of connections upon which we'll issue an alert",
         short: '-c NUMBER',
         long: '--critnum NUMBER',
         default: 128

  option :usepc,
         description: 'Use percentage of defined max connections instead of absolute number',
         short: '-a',
         long: '--percentage',
         default: false


  def connect
    section = nil
    if config[:ini]
      ini = IniFile.load(config[:ini])
      section = ini['client']
    end

    @connection_info = {
      host:       config[:hostname],
      username:  (config[     :ini] ? section[    'user'] : config[:user]),
      password:  (config[     :ini] ? section['password'] : config[:password]),
      database:   config[:database],
      port:       config[    :port],
      socket:     config[  :socket],
    }
    @client = Mysql2::Client.new(@connection_info)
  end


  def run_test
    max_con = @client
              .query("SHOW VARIABLES LIKE 'max_connections'")
              .first
              .fetch('Value')
              .to_i
    used_con = @client
               .query("SHOW GLOBAL STATUS LIKE 'Threads_connected'")
               .first
               .fetch('Value')
               .to_i
    if config[:usepc]
      pc = used_con.fdiv(max_con) * 100
      critical "Max connections reached in MySQL: #{used_con} out of #{max_con}" if pc >= config[:maxcrit].to_i
      warning "Max connections reached in MySQL: #{used_con} out of #{max_con}" if pc >= config[:maxwarn].to_i
      ok "Max connections is under limit in MySQL: #{used_con} out of #{max_con}" # rubocop:disable Style/IdenticalConditionalBranches
    else
      critical "Max connections reached in MySQL: #{used_con} out of #{max_con}" if used_con >= config[:maxcrit].to_i
      warning "Max connections reached in MySQL: #{used_con} out of #{max_con}" if used_con >= config[:maxwarn].to_i
      ok "Max connections is under limit in MySQL: #{used_con} out of #{max_con}" # rubocop:disable Style/IdenticalConditionalBranches
    end
  end


  def run
    connect
    run_test
  rescue Mysql2::Error => e
    errstr = "Error code: #{e.errno} Error message: #{e.error}"
    critical "#{self.class.name} failed: #{errstr} SQLSTATE: #{e.sqlstate}" if e.respond_to?('sqlstate')
  rescue => e
    critical "#{self.class.name} unknown error: #{e.message}\n\n#{e.backtrace.join('\n')}"
  ensure
    @client.close if @client
  end
end

