# fluent-plugin-http-cwm

![GitHub Workflow Status (branch)](https://img.shields.io/github/workflow/status/iamAzeem/fluent-plugin-http-cwm/ci/main?label=build&style=flat-square)
![GitHub Workflow Status (branch)](https://img.shields.io/github/workflow/status/iamAzeem/fluent-plugin-http-cwm/publish/main?label=publish&style=flat-square)
![GitHub release (latest by date)](https://img.shields.io/github/v/release/iamAzeem/fluent-plugin-http-cwm?style=flat-square)
[![License: Apache-2.0](https://img.shields.io/badge/license-Apache-blue.svg?style=flat-square)](https://github.com/iamAzeem/fluent-plugin-http-cwm/blob/master/LICENSE)

[![RubyGems Downloads](https://img.shields.io/gem/dt/fluent-plugin-http-cwm?color=blue&style=flat-square)](https://rubygems.org/gems/fluent-plugin-http-cwm)
![Lines of code](https://img.shields.io/tokei/lines/github/iamAzeem/fluent-plugin-http-cwm?label=LOC&style=flat-square)
![GitHub code size in bytes](https://img.shields.io/github/languages/code-size/iamAzeem/fluent-plugin-http-cwm?style=flat-square)
![GitHub repo size](https://img.shields.io/github/repo-size/iamAzeem/fluent-plugin-http-cwm?style=flat-square)

- [Overview](#overview)
- [Installation](#installation)
  - [RubyGems](#rubygems)
  - [Bundler](#bundler)
- [Configuration](#configuration)
  - [`<redis>` section (optional) (single)](#redis-section-optional-single)
  - [Sample Configuration](#sample-configuration)
- [Contribute](#contribute)
- [Publish the gem](#publish-the-gem)
- [License](#license)

## Overview

[Fluentd](https://fluentd.org/) HTTP input plugin for
[CloudWebManage](https://github.com/CloudWebManage) Logging Component.

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

| metric              | description                                        |
| :------------------ | :------------------------------------------------- |
| `bytes_in`          | size of Request header and its Content-Length      |
| `bytes_out`         | size of Response header and its Content-Length     |
| `num_requests_in`   | count of APIs [WebUpload, PutObject, DeleteObject] |
| `num_requests_out`  | count of APIs [WebDownload, GetObject]             |
| `num_requests_misc` | count of APIs other than `in` and `out`            |

## Installation

### RubyGems

```shell
gem install fluent-plugin-http-cwm
```

### Bundler

Add the following line to your Gemfile:

```ruby
gem 'fluent-plugin-http-cwm'
```

And then execute:

```shell
bundle
```

## Configuration

- `host` (string) (optional): The address to bind to.
  - Default value: `localhost`.
- `port` (integer) (optional): The port to listen to.
  - Default value: `8080`.
- `tag` (string) (required): The tag for the event.

### `<redis>` section (optional) (single)

- `host` (string) (optional): The address of Redis server.
  - Default value: `localhost`.
- `port` (integer) (optional): The port of Redis server.
  - Default value: `6379`.
- `db` (integer) (optional): The db to use.
  - Default value: `0`.
- `grace_period` (time) (optional): The grace period for last action update.
  - Default value: `300s`.
- `flush_interval` (time) (optional): The flush interval to send metrics.
  - Default value: `300s`.
- `last_update_prefix` (string) (optional): The prefix for last update key.
  - Default value: `deploymentid:last_action`.
- `metrics_prefix` (string) (optional): The prefix for metrics key.
  - Default value: `deploymentid:minio-metrics`.

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
    db                    0
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

- Fork the project.
- Check out the latest `main` branch.
- Create a feature or bugfix branch from `main`.
- Commit and push your changes.
- Make sure to add and run tests locally: `bundle exec rake test`.
- Run Rubocop locally and fix all the lint warnings.
- Make sure to update [Gemfile.lock](Gemfile.lock): `sudo bundle update`.
- Submit the PR.

## Publish the gem

The gem is published via the [publish.yml](.github/workflows/publish.yml)
Workflow on tagging. The tag must be of the format `v0.3.0`. This workflow
depends on the successful completion of the [ci.yml](.github/workflows/ci.yml)
workflow and then it looks for the tag. So, make sure that all the CI issues are
resolved before creating a new tag. If there are issues while publishing the gem
i.e. publish workflow doesn't work properly, you can delete and then recreate
the tag to retrigger this workflow.

## License

[Apache 2.0](./LICENSE)
