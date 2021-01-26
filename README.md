# fluent-plugin-http-cwm

[![License: Apache-2.0](https://img.shields.io/badge/License-Apache-blue.svg?style=flat-square)](https://github.com/iamAzeem/fluent-plugin-http-cwm/blob/master/LICENSE)
[![RubyGems Downloads](https://img.shields.io/gem/dt/fluent-plugin-http-cwm?color=blue&style=flat-square&label=Downloads)](https://rubygems.org/gems/fluent-plugin-http-cwm)

[Fluentd](https://fluentd.org/) HTTP input plugin for
[CloudWebManage](https://github.com/CloudWebManage) Logging Component.

## Overview

This plugin:

1. receives the incoming JSON logs from MinIO using an HTTP endpoint,
2. validates the required JSON fields,
3. aggregates the logging metrics,
4. flushes the aggregated metrics to the configured Redis instance; and,
5. routes logs to the configured log targets e.g. S3, ElasticSearch, etc.

```text
  +------------------+
  |       MinIO      |
  +------------------+
            |
            | JSON
            | logs
            |
            v
  +------------------+
  |     fluentd      |
  |                  |
  | +--------------+ |                   +-----------------+
  | |   http_cwm   | |     [metrics]     |      Redis      |
  | |   (input)    |-------------------->|      Server     |
  | +--------------+ |                   +-----------------+
  |                  |
  | +--------------+ |                   +-----------------+
  | |      s3      | |     [raw logs]    |       S3        |
  | |   (output)   |-------------------->|   (log target)  |
  | +--------------+ |                   +-----------------+
  |                  |
  | +--------------+ |                   +-----------------+
  | |elasticsearch | |     [raw logs]    |  ElasticSearch  |
  | |   (output)   |-------------------->|  (log target)   |
  | +--------------+ |                   +-----------------+
  |                  |
  +------------------+
```

The following metrics are aggregated:

| metric              | description                                         |
|:--------------------|:----------------------------------------------------|
| `bytes_in`          | size of Request header and its Content-Length       |
| `bytes_out`         | size of Response header and its Content-Length      |
| `num_requests_in`   | count of APIs [WebUpload, PutObject, DeleteObject]  |
| `num_requests_out`  | count of APIs [WebDownload, GetObject]              |
| `num_requests_misc` | count of APIs other than `in` and `out`             |

## Installation

### RubyGems

```shell
gem install fluent-plugin-http-cwm
```

### Bundler

Add the following line to your Gemfile:

```ruby
gem "fluent-plugin-http-cwm"
```

And then execute:

```shell
bundle
```

## Configuration

* `host` (string) (optional): The address to bind to.
  * Default value: `localhost`.
* `port` (integer) (optional): The port to listen to.
  * Default value: `8080`.
* `tag` (string) (required): The tag for the event.

### `<redis>` section (optional) (single)

* `host` (string) (optional): The address of Redis server.
  * Default value: `localhost`.
* `port` (integer) (optional): The port of Redis server.
  * Default value: `6379`.
* `grace_period` (time) (optional): The grace period for last update.
  * Default value: `300s`.
* `flush_interval` (time) (optional): The flush interval to send metrics.
  * Default value: `300s`.
* `last_update_prefix` (string) (optional): The prefix for last update key.
  * Default value: `deploymentid:last_action`.
* `metrics_prefix` (string) (optional): The prefix for metrics key.
  * Default value: `deploymentid:minio-metrics`.

### Sample Configuration

```text
# Endpoint for incoming logs: http://host:port/<tag>

# HTTP Input
<source>
  @type                   http_cwm
  @id                     http_cwm_logs

  host                    localhost
  port                    8080

  tag                     logs

  <redis>
    host                  localhost
    port                  6379
    grace_period          10s
    flush_interval        10s
    last_update_prefix    deploymentid:last_action
    metrics_prefix        deploymentid:minio-metrics
  </redis>
</source>

# Output e.g. ElasticSearch, S3, etc.
<match logs>
  @type                   elasticsearch
  # ...
</match>
```

The environment variables may also be used for the configuration.

Example:

```text
<source>
  @type                   http_cwm
  @id                     http_cwm_logs

  host                    "#{ENV['HTTP_HOST']}"
  port                    "#{ENV['HTTP_PORT']}"

  # ...
</source>
 ```

## Contribute

* Fork the project.
* Check out the latest `main` branch.
* Create a feature or bugfix branch from `main`.
* Commit and push your changes.
* Make sure to add tests.
* Run Rubocop locally and fix all the lint warnings.
* Submit the final the PR.

## Copyright

* Copyright &copy; 2020 Azeem Sajid
* License
  * Apache License, Version 2.0
