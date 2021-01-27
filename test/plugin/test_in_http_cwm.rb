# frozen-string-literal: true

require 'helper'
require 'fluent/plugin/in_http_cwm'
require 'net/http'

class CwmHttpInputTest < Test::Unit::TestCase
  setup do
    Fluent::Test.setup

    @default_conf = %(
      tag       test
    )
  end

  def create_driver(conf)
    Fluent::Test::Driver::Input.new(Fluent::Plugin::CwmHttpInput).configure(conf)
  end

  sub_test_case 'configuration' do
    test 'default configuration test' do
      driver = create_driver(@default_conf)
      plugin = driver.instance
      assert_equal Fluent::Plugin::CwmHttpInput, plugin.class
      assert_equal 'localhost', plugin.host
      assert_equal 8080, plugin.port
    end

    test 'redis default configuration test' do
      conf = %(
        tag     test
        <redis>
        </redis>
      )

      driver = create_driver(conf)
      plugin = driver.instance
      redis = plugin.redis_config
      assert_equal 'localhost', redis.host
      assert_equal 6379, redis.port
      assert_equal '300s', redis.grace_period
      assert_equal '300s', redis.flush_interval
      assert_equal 'deploymentid:last_action', redis.last_update_prefix
      assert_equal 'deploymentid:minio-metrics', redis.metrics_prefix
    end
  end

  sub_test_case 'route#emit' do
    test 'emit test' do
      driver = create_driver(@default_conf)

      res_codes = []
      lines = 0

      driver.run do
        File.readlines('./test/logs.txt').each do |line|
          res = post('/test', line.chomp)
          res_codes << res.code
          lines += 1
        end
      end

      assert_equal lines, res_codes.size
      assert_equal '200', res_codes[0]
      assert_equal 1, res_codes.uniq.size
    end
  end

  private

  def post(path, body)
    http = Net::HTTP.new('127.0.0.1', 8080)
    header = { 'Content-Type' => 'application/json' }
    req = Net::HTTP::Post.new(path, header)
    req.body = body
    http.request(req)
  end
end
