import Config

config :logger,
  backends: [:console]

config :logger, :console,
  level: :info

import_config "#{config_env()}.exs"
