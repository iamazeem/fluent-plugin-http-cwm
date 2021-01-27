# frozen-string-literal: true

require 'helper'
require 'fluent/plugin/in_http_cwm'

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
      driver.run(timeout: 0.5)

      driver.events.each do |tag, time, record|
        assert_equal('test', tag)
        assert_equal({ 'key' => 'value' }, record)
        assert(time.is_a?(Fluent::EventTime))
      end
    end
  end
end
