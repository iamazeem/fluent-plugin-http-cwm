# frozen-string-literal: true

#
# Copyright 2020 Azeem Sajid
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'fluent/plugin/input'
require 'fluent/config/error'
require 'fluent/plugin_helper/http_server'
require 'fluent/plugin_helper/timer'
require 'webrick/httputils'
require 'json'
require 'redis'

FMT_DATETIME = '%Y-%m-%dT%H:%M:%S.%8NZ'

module Fluent
  module Plugin
    # Custom HTTP Input Plugin class for CWM
    class CwmHttpInput < Fluent::Plugin::Input
      Fluent::Plugin.register_input('http_cwm', self)

      helpers :http_server, :event_emitter, :timer

      desc 'The address to bind to.'
      config_param :host, :string, default: 'localhost'

      desc 'The port to listen to.'
      config_param :port, :integer, default: 8080

      desc 'The tag for the event.'
      config_param :tag, :string

      desc 'The Redis configuration section for flushing metrics.'
      config_section :redis, required: false, multi: false, init: true, param_name: :redis_config do
        desc 'The address of Redis server.'
        config_param :host, :string, default: 'localhost'

        desc 'The port of Redis server.'
        config_param :port, :integer, default: 6379

        desc 'The db to use.'
        config_param :db, :integer, default: 0

        desc 'The grace period for last action update.'
        config_param :grace_period, :time, default: '300s'

        desc 'The flush interval to send metrics.'
        config_param :flush_interval, :time, default: '300s'

        desc 'The prefix for last update key.'
        config_param :last_update_prefix, :string, default: 'deploymentid:last_action'

        desc 'The prefix for metrics key.'
        config_param :metrics_prefix, :string, default: 'deploymentid:minio-metrics'
      end

      def initialize
        super

        @redis = nil
        @deployment_api_metrics = default_api_metrics_hash

        @last_action_queue = Queue.new
        @last_action_entry = []
      end

      def configure(conf)
        super

        set_up_redis
      end

      def start
        super

        # start interval timer to flush api metrics
        timer_execute(:api_metrics_flush_timer, @redis_config.flush_interval) do
          flush_api_metrics
        end

        # start interval timer to flush last action entry
        timer_execute(:last_action_flush_timer, '1s') do
          if @last_action_entry.empty?
            @last_action_entry = @last_action_queue.deq.split('|')
            log.debug("Dequed last action entry. #{@last_action_entry}")
          else
            deploymentid, last_action = @last_action_entry
            @last_action_entry = [] if update_deployment_last_action(deploymentid, last_action)
          end
        end

        log.info("Starting HTTP server [#{@host}:#{@port}]...")
        http_server_create_http_server(:http_server, addr: @host, port: @port, logger: log) do |server|
          server.post("/#{tag}") do |req|
            data = parse_data(req.body)
            route(data) if update_deployment_metrics(data)

            # return HTTP 200 OK response with emtpy body
            [200, { 'Content-Type' => 'text/plain' }, nil]
          end
        end
      end

      private

      def default_api_metrics_hash
        Hash.new do |h, k|
          h[k] = {
            'bytes_in' => 0, 'bytes_out' => 0,
            'num_requests_in' => 0, 'num_requests_out' => 0, 'num_requests_misc' => 0
          }
        end
      end

      def set_up_redis
        host = @redis_config.host
        port = @redis_config.port
        db = @redis_config.db
        log.info("Connecting with Redis [address: #{host}:#{port}, db: #{db}]")
        @redis = Redis.new(host: host, port: port, db: db)
        ready = false
        until ready
          sleep(1)
          begin
            @redis.ping
            ready = true
          rescue StandardError => e
            log.error("Unable to connect to Redis server! ERROR: '#{e}'. Retrying...")
          end
        end
      end

      def parse_data(data)
        JSON.parse(data)
      rescue StandardError => e
        log.debug("ERROR: #{e}")
        nil
      end

      def route(data)
        time = Fluent::Engine.now
        record = { 'message' => data }
        router.emit(@tag, time, record)
      end

      def datetime_diff_in_secs(dt_begin, dt_end)
        seconds = ((dt_end - dt_begin) * 24 * 60 * 60)
        seconds.to_i
      end

      def update_deployment_last_action(deploymentid, last_action)
        key = "#{@redis_config.last_update_prefix}:#{deploymentid}"
        log.debug("Checking existing last action entry [key: #{key}]")
        lastval = @redis.get(key)

        is_grace_period_expired = false
        if lastval
          curdt = DateTime.now
          lastdt = DateTime.parse(lastval, FMT_DATETIME)
          dt_diff_secs = datetime_diff_in_secs(lastdt, curdt)
          log.debug("Current  Data/Time: #{curdt}")
          log.debug("Previous Date/Time: #{lastdt}")
          log.debug("Date/Time diff (s): #{dt_diff_secs}")

          if dt_diff_secs >= @redis_config.grace_period
            is_grace_period_expired = true
            log.debug("Grace period expired for last action update. [#{@redis_config.grace_period}]")
          end
        else
          log.debug('Last action entry does not exist. It will be set for the first time.')
        end

        if lastdt.nil? || is_grace_period_expired
          log.debug('Updating deployment last action')
          last_action = DateTime.parse(last_action, FMT_DATETIME)
          @redis.set(key, last_action)
          log.debug("Updated last action entry [#{key} => #{last_action}]")
          true
        else
          false
        end
      rescue StandardError => e
        log.error("Unable to update last action! ERROR: '#{e}'.")
        false
      end

      def enque_last_action_entry(deploymentid)
        last_action = DateTime.now
        entry = "#{deploymentid}|#{last_action}"
        @last_action_queue.enq(entry)
        log.debug("Enqued last action entry. [#{entry}]")
      end

      def validate_and_get_value(data_hash, key)
        value = data_hash[key]
        log.debug("missing '#{key}': #{data_hash.to_json}") unless value
        value
      end

      def update_deployment_metrics(data)
        return false unless data

        log.debug('Updating deployment metrics')

        deploymentid = validate_and_get_value(data, 'deploymentid')
        return false unless deploymentid

        enque_last_action_entry(deploymentid)

        api_data = validate_and_get_value(data, 'api')
        return false unless api_data

        api_name = validate_and_get_value(api_data, 'name')
        return false unless api_name

        response_header_data = validate_and_get_value(data, 'responseHeader')
        return false unless response_header_data

        request_header_data = validate_and_get_value(data, 'requestHeader')
        return false unless request_header_data

        response_content_length = response_header_data['Content-Length'].to_i
        response_content_length += response_header_data.to_s.length

        response_is_cached = (response_header_data['X-Cache'] == 'HIT')

        request_content_length = request_header_data['Content-Length'].to_i
        request_content_length += request_header_data.to_s.length

        update_deployment_api_metrics(deploymentid, api_name, request_content_length, response_content_length, response_is_cached)

        true
      end

      def get_request_type(api_name)
        in_apis = %w[WebUpload PutObject DeleteObject].freeze
        out_apis = %w[WebDownload GetObject].freeze
        return 'in' if in_apis.include?(api_name)
        return 'out' if out_apis.include?(api_name)

        'misc'
      end

      def update_deployment_api_metrics(deploymentid, api_name, request_content_length, response_content_length, response_is_cached)
        log.debug('Updating deployment API metrics')

        request_type = get_request_type(api_name)
        log.debug("#{deploymentid}.#{api_name}: (type=#{request_type}, req_size=#{request_content_length}, res_size=#{response_content_length}, res_cache=#{response_is_cached})")

        metrics = @deployment_api_metrics[deploymentid]
        metrics['bytes_in'] += request_content_length
        metrics['bytes_out'] += response_content_length
        metrics["num_requests_#{request_type}"] += 1
        @deployment_api_metrics[deploymentid] = metrics
      end

      def flush_api_metrics
        return if @deployment_api_metrics.empty?

        log.debug("Flushing metrics: #{@deployment_api_metrics}")

        begin
          @redis.pipelined do
            @deployment_api_metrics.each do |deploymentid, metrics|
              metrics.each do |metric, value|
                @redis.incrby("#{@redis_config.metrics_prefix}:#{deploymentid}:#{metric}", value) if value.positive?
              end
            end
          end

          @deployment_api_metrics = default_api_metrics_hash

          log.debug('Flushing complete!')
        rescue StandardError => e
          log.error("Unable to flush metrics! ERROR: '#{e}'.")
        end
      end
    end
  end
end
