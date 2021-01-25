# frozen-string-literal: true

lib = File.expand_path('../lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

Gem::Specification.new do |spec|
  spec.name           = 'fluent-plugin-http-cwm'
  spec.version        = '0.1.0'
  spec.authors        = ['Azeem Sajid']
  spec.email          = ['azeem.sajid@gmail.com']

  spec.summary        = 'fluentd HTTP Input Plugin for CloudWebManage Logging Component'
  spec.description    = 'fluentd HTTP Input Plugin for CloudWebManage Logging Component with Log Metrics Support'
  spec.homepage       = 'https://github.com/iamAzeem/fluent-plugin-http-cwm'
  spec.license        = 'Apache-2.0'

  test_files, files   = `git ls-files -z`.split("\x0").partition { |f| f.match(%r{^(test|spec|features)/}) }
  spec.files          = files
  spec.executables    = files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files     = test_files
  spec.require_paths  = ['lib']

  spec.add_development_dependency 'bundler', '>= 1.14', '< 3'
  spec.add_development_dependency 'rake', '~> 12.3', '>= 12.3.3'
  spec.add_development_dependency 'rubocop', '~> 0.8', '>= 0.8.0'
  spec.add_development_dependency 'test-unit', '~> 3.0'
  spec.add_runtime_dependency 'fluentd', ['>= 0.14.10', '< 2']
  spec.add_runtime_dependency 'json', '~> 2.3', '>= 2.3.0'
  spec.add_runtime_dependency 'redis', '~> 4.2', '>= 4.2.5'
end
