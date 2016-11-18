#!/usr/bin/env ruby
#
# Push mysql stats into graphite
# ===
#
# NOTE: This plugin will attempt to get replication stats but the user
# must have SUPER or REPLICATION CLIENT privileges to run 'SHOW SLAVE
# STATUS'. It will silently ignore and continue if 'SHOW SLAVE STATUS'
# fails for any reason. The key 'slaveLag' will not be present in the
# output.
#
# Copyright 2012 Pete Shima <me@peteshima.com>
# Additional hacks by Joe Miller - https://github.com/joemiller
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

require 'sensu-plugin/metric/cli'
require 'mysql2'
require 'socket'
require 'inifile'

class MysqlGraphiteMetrics < Sensu::Plugin::Metric::CLI::Graphite

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

  option :scheme,
         description: 'Metric naming scheme, text to prepend to metric',
         short: '-S SCHEME',
         long: '--scheme SCHEME',
         default: "#{Socket.gethostname}.mysql"

  option :scheme_append,
         description: 'Metric naming scheme addendum. placed right after the prepend (usually the server name) to distinguish for instance different targets. Defaults to hostname',
         short: '-A APPEND_STRING',
         long:  '--scheme-append'

  option :no_slave,
         description: 'skip slave metrics. might be necessary to skip those metrics due to permissions',
         short: '-n',
         long:  '--no-slave',
         boolean: true,
         default: false

  option :verbose,
         short: '-v',
         long: '--verbose',
         boolean: true


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


  def self.mysql_metrics
    metrics = {
      'general' => {
        'Bytes_received' =>         'rxBytes',
        'Bytes_sent' =>             'txBytes',
        'Key_read_requests' =>      'keyRead_requests',
        'Key_reads' =>              'keyReads',
        'Key_write_requests' =>     'keyWrite_requests',
        'Key_writes' =>             'keyWrites',
        'Binlog_cache_use' =>       'binlogCacheUse',
        'Binlog_cache_disk_use' =>  'binlogCacheDiskUse',
        'Max_used_connections' =>   'maxUsedConnections',
        'Aborted_clients' =>        'abortedClients',
        'Aborted_connects' =>       'abortedConnects',
        'Threads_connected' =>      'threadsConnected',
        'Open_files' =>             'openFiles',
        'Open_tables' =>            'openTables',
        'Opened_tables' =>          'openedTables',
        'Prepared_stmt_count' =>    'preparedStmtCount',
        'Seconds_Behind_Master' =>  'slaveLag',
        'Select_full_join' =>       'fullJoins',
        'Select_full_range_join' => 'fullRangeJoins',
        'Select_range' =>           'selectRange',
        'Select_range_check' =>     'selectRange_check',
        'Select_scan' =>            'selectScan',
        'Slow_queries' =>           'slowQueries'
      },
      'querycache' => {
        'Qcache_queries_in_cache' =>  'queriesInCache',
        'Qcache_hits' =>              'cacheHits',
        'Qcache_inserts' =>           'inserts',
        'Qcache_not_cached' =>        'notCached',
        'Qcache_lowmem_prunes' =>     'lowMemPrunes'
      },
      'commands' => {
        'Com_admin_commands' => 'admin_commands',
        'Com_begin' =>          'begin',
        'Com_change_db' =>      'change_db',
        'Com_commit' =>         'commit',
        'Com_create_table' =>   'create_table',
        'Com_drop_table' =>     'drop_table',
        'Com_show_keys' =>      'show_keys',
        'Com_delete' =>         'delete',
        'Com_create_db' =>      'create_db',
        'Com_grant' =>          'grant',
        'Com_show_processlist' => 'show_processlist',
        'Com_flush' =>          'flush',
        'Com_insert' =>         'insert',
        'Com_purge' =>          'purge',
        'Com_replace' =>        'replace',
        'Com_rollback' =>       'rollback',
        'Com_select' =>         'select',
        'Com_set_option' =>     'set_option',
        'Com_show_binlogs' =>   'show_binlogs',
        'Com_show_databases' => 'show_databases',
        'Com_show_fields' =>    'show_fields',
        'Com_show_status' =>    'show_status',
        'Com_show_tables' =>    'show_tables',
        'Com_show_variables' => 'show_variables',
        'Com_update' =>         'update',
        'Com_drop_db' =>        'drop_db',
        'Com_revoke' =>         'revoke',
        'Com_drop_user' =>      'drop_user',
        'Com_show_grants' =>    'show_grants',
        'Com_lock_tables' =>    'lock_tables',
        'Com_show_create_table' => 'show_create_table',
        'Com_unlock_tables' =>  'unlock_tables',
        'Com_alter_table' =>    'alter_table'
      },
      'counters' => {
        'Handler_write' =>              'handlerWrite',
        'Handler_update' =>             'handlerUpdate',
        'Handler_delete' =>             'handlerDelete',
        'Handler_read_first' =>         'handlerRead_first',
        'Handler_read_key' =>           'handlerRead_key',
        'Handler_read_next' =>          'handlerRead_next',
        'Handler_read_prev' =>          'handlerRead_prev',
        'Handler_read_rnd' =>           'handlerRead_rnd',
        'Handler_read_rnd_next' =>      'handlerRead_rnd_next',
        'Handler_commit' =>             'handlerCommit',
        'Handler_rollback' =>           'handlerRollback',
        'Handler_savepoint' =>          'handlerSavepoint',
        'Handler_savepoint_rollback' => 'handlerSavepointRollback'
      },
      'innodb' => {
        'Innodb_buffer_pool_pages_total' =>   'bufferTotal_pages',
        'Innodb_buffer_pool_pages_free' =>    'bufferFree_pages',
        'Innodb_buffer_pool_pages_dirty' =>   'bufferDirty_pages',
        'Innodb_buffer_pool_pages_data' =>    'bufferUsed_pages',
        'Innodb_page_size' =>                 'pageSize',
        'Innodb_pages_created' =>             'pagesCreated',
        'Innodb_pages_read' =>                'pagesRead',
        'Innodb_pages_written' =>             'pagesWritten',
        'Innodb_row_lock_current_waits' =>    'currentLockWaits',
        'Innodb_row_lock_waits' =>            'lockWaitTimes',
        'Innodb_row_lock_time' =>             'rowLockTime',
        'Innodb_data_reads' =>                'fileReads',
        'Innodb_data_writes' =>               'fileWrites',
        'Innodb_data_fsyncs' =>               'fileFsyncs',
        'Innodb_log_writes' =>                'logWrites',
        'Innodb_rows_updated' =>              'rowsUpdated',
        'Innodb_rows_read' =>                 'rowsRead',
        'Innodb_rows_deleted' =>              'rowsDeleted',
        'Innodb_rows_inserted' =>             'rowsInserted'
      },
      'configuration' => {
        'max_connections'         =>          'MaxConnections',
        'Max_prepared_stmt_count' =>          'MaxPreparedStmtCount'
      }
    }
  end


  # props to https://github.com/coredump/hoardd/blob/master/scripts-available/mysql.coffee
  def run_test
    scheme_append = config[:scheme_append] ? config[:scheme_append] : config[:hostname]
    results = @client.query('SHOW GLOBAL STATUS')
    results.each do |row|
      self.class.mysql_metrics.each do |category, var_mapping|
        if var_mapping.key?(row['Variable_name'])
          output "#{config[:scheme]}.#{scheme_append}.#{category}.#{var_mapping[row['Variable_name']]}", row['Value']
        end
      end
    end

    unless config[:no_slave]
      slave_results = @client.query('SHOW SLAVE STATUS')
      # should return a single element array containing one hash
      # #YELLOW
      if slave_results.any?
        slave_results.first.each do |key, value|
          if self.class.mysql_metrics['general'].include?(key)
            # Replication lag being null is bad, very bad, so negativate it here
            value = -1 if key == 'Seconds_Behind_Master' && value.nil?
            output "#{config[:scheme]}.#{scheme_append}.general.#{self.class.mysql_metrics['general'][key]}", value
          end
        end
      end
    end

    variables_results = @client.query('SHOW GLOBAL VARIABLES')
    category = 'configuration'
    variables_results.each do |row|
      self.class.mysql_metrics[category].each do |metric, desc|
        if metric.casecmp(row['Variable_name']) == 0
          output "#{config[:scheme]}.#{scheme_append}.#{category}.#{desc}", row['Value']
        end
      end
    end

    ok
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

