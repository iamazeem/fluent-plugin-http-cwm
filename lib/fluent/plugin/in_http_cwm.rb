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

        desc 'The grace period for last update.'
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
      end

      def configure(conf)
        super

        set_up_redis
      end

      def start
        super

        # set up timer for flush interval
        timer_execute(:metrics_flush_timer, @redis_config.flush_interval) do
          flush_api_metrics
        end

        log.info("Starting HTTP server [#{@host}:#{@port}]...")
        http_server_create_http_server(:http_server, addr: @host, port: @port, logger: log) do |server|
          server.post("/#{tag}") do |req|
            data = parse_data(req.body)
            route(data) if update_deployment_metrics(data)

            # return HTTP 200 OK response to MinIO
            [200, { 'Content-Type' => 'text/plain' }, nil]
          end
        end
      end

      def default_api_metrics_hash
        Hash.new do |h, k|
          h[k] = {
            'bytes_in' => 0, 'bytes_out' => 0,
            'num_requests_in' => 0, 'num_requests_out' => 0, 'num_requests_misc' => 0
          }
        end
      end

      def set_up_redis
        log.info("Connecting with Redis [#{@redis_config.host}:#{@redis_config.port}]")
        @redis = Redis.new(host: @redis_config.host, port: @redis_config.port)
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

      def days_to_seconds(days)
        days * 24 * 60 * 60
      end

      def update_deployment_last_action(deploymentid)
        log.debug('Updating deployment last action')

        key = "#{@redis_config.last_update_prefix}:#{deploymentid}"
        curdt = DateTime.now

        begin
          lastval = @redis.get(key)
          lastdt = DateTime.parse(lastval, FMT_DATETIME) if lastval
          if lastdt.nil? || days_to_seconds((curdt - lastdt).to_i) >= @redis_config.grace_period
            log.debug('Setting last action')
            @redis.set(key, curdt.strftime(FMT_DATETIME))
          end
        rescue StandardError => e
          log.error("Unable to update last action! ERROR: '#{e}'.")
        end
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

        update_deployment_last_action(deploymentid)

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
