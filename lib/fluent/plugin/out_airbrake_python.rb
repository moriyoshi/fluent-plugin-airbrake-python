# Copyright 2014 Moriyoshi Koizumi
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#     http://www.apache.org/licenses/LICENSE-2.0
# 
#     Unless required by applicable law or agreed to in writing, software
#     distributed under the License is distributed on an "AS IS" BASIS,
#     WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#     See the License for the specific language governing permissions and
#     limitations under the License.

require 'net/http'
require 'airbrake'
require 'airbrake/version'
require 'airbrake/sender'
require 'airbrake/configuration'
require 'airbrake/notice'
require 'airbrake/backtrace'
require 'airbrake/utils/rack_filters'
require 'airbrake/utils/params_cleaner'

class Fluent::AirbrakePythonOutput < Fluent::Output
  Fluent::Plugin.register_output('airbrake_python', self)

  PY_LOGLEVEL_MAP = {
    'CRITICAL' => 50,
    'FATAL'    => 50,
    'ERROR'    => 40,
    'WARNING'  => 30,
    'WARN'     => 30,
    'INFO'     => 20,
    'DEBUG'    => 10,
    'NOTSET'   =>  0
  }

  config_param :host, :string, :default => nil
  config_param :port, :integer, :default => nil
  config_param :proxy_host, :string, :default => nil
  config_param :proxy_port, :integer, :default => nil
  config_param :proxy_user, :string, :default => nil
  config_param :proxy_pass, :string, :default => nil
  config_param :protocol, :string, :default => 'ssl'
  config_param :param_filters, :string, :default => nil
  config_param :development_environments, :string, :default => nil
  config_param :development_lookup, :bool, :default => false
  config_param :environment_name, :string, :default => 'production'
  config_param :project_root, :string, :default => ''
  config_param :notifier_name, :string, :default => nil
  config_param :notifier_version, :string, :default => nil
  config_param :notifier_url, :string, :default => nil
  config_param :user_information, :string, :default => nil
  config_param :framework, :string, :default => nil
  config_param :secure, :bool, :default => true
  config_param :use_system_ssl_cert_chain, :bool, :default => true
  config_param :http_open_timeout, :integer, :default => nil
  config_param :http_read_timeout, :integer, :default => nil
  config_param :project_id, :string, :default => nil
  config_param :api_key, :string
  config_param :message_regexp, :string, :default => '.*'
  config_param :message_template, :string, :default => '\\0'
  config_param :loglevel, :string, :default => 'DEBUG'
  config_param :cgi_data_dump_key, :string, :default => nil
  config_param :parameters_dump_key, :string, :default => nil
  config_param :session_dump_key, :string, :default => nil

  class Notice < Airbrake::Notice
    def initialize(args)
      backtrace = args.delete(:backtrace)
      super
      @error_class = args[:error_class]
      @backtrace = backtrace
    end
  end

  def configure(conf)
    super

    aconf = Airbrake::Configuration.new
    aconf.host = @host
    aconf.port = @port ? @port: (@secure ? 443: 80)
    aconf.proxy_host = @proxy_host
    aconf.proxy_port = @proxy_port
    aconf.proxy_user = @proxy_user
    aconf.proxy_pass = @proxy_pass
    aconf.param_filters = @param_filters.split(/\s+/) if @param_filters
    aconf.development_environments = @development_environments.split(/\s+/) if @development_environments
    aconf.development_lookup = @development_lookup
    aconf.environment_name = @environment_name
    aconf.project_root = @project_root
    aconf.notifier_name = @notifier_name if @notifier_name
    aconf.notifier_version = @notifier_version if @notifier_version
    aconf.notifier_url = @notifier_url if @notifier_url
    aconf.user_information = @user_information if @user_information
    aconf.framework = @framework if @framework
    aconf.secure = @secure
    aconf.use_system_ssl_cert_chain = @use_system_ssl_cert_chain
    aconf.http_open_timeout = @http_open_timeout if @http_open_timeout
    aconf.http_read_timeout = @http_read_timeout if @http_read_timeout
    aconf.project_id = @project_id
    aconf.api_key = @api_key

    @aconf = aconf
    @sender = Airbrake::Sender.new(aconf)
    @message_regexp = Regexp.new(@message_regexp, Regexp::MULTILINE)
    @loglevel = Integer(@loglevel) rescue PY_LOGLEVEL_MAP[@loglevel]
  end

  def notification_needed(tag, time, record)
    if record['sys_levelno']
      record['sys_levelno'] >= @loglevel
    else
      nil
    end
  end

  def build_component_name_py(record)
    record['sys_name']
  end

  def build_action_name_py(record)
    record['sys_funcname']
  end

  def build_message_py(record)
    if record['message']
      record['message'].sub(@message_regexp, @message_template)
    else
      nil
    end
  end

  def build_cgi_data_dump(record)
    if @cgi_data_dump_key
      record[@cgi_data_dump_key]
    else
      nil
    end
  end

  def build_parameters_dump(record)
    if @parameters_dump_key
      record[@parameters_dump_key]
    else
      nil
    end
  end

  def build_session_dump(record)
    if @session_dump_key
      record[@session_dump_key]
    else
      nil
    end
  end

  def notice_from_py_record(aconf, tag, record)
    exc_info_rec = record['sys_exc_info']
    return nil unless exc_info_rec
    error_class = nil
    backtrace = nil
    if exc_info_rec
      error_class = exc_info_rec['type']
      backtrace = Airbrake::Backtrace.new(
        exc_info_rec['traceback'].map { |f|
          Airbrake::Backtrace::Line.new(f[0], f[1], f[2])
        }
      )
    end

    Notice.new(
      aconf.merge(
        :error_class    => error_class,
        :backtrace      => backtrace,
        :error_message  => build_message_py(record),
        :component      => build_component_name_py(record),
        :action         => build_action_name_py(record),
        :hostname       => record['sys_host'],
        :project_id     => aconf[:project_id] || tag,
        :cgi_data       => build_cgi_data_dump(record) || {},
        :session_data   => build_session_dump(record) || {},
        :parameters     => build_parameters_dump(record) || {},
      )
    )
  end


  def build_notice(tag, time, record)
    if notification_needed(tag, time, record)
      notice_from_py_record(@aconf, tag, record)
    end
  end

  def emit(tag, es, chain)
    es.each do |time, record|
      notice = build_notice(tag, time, record)
      @sender.send_to_airbrake(notice) if notice
    end
    chain.next
  end
end
