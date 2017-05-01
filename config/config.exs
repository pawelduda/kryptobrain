# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
use Mix.Config

config :krypto_brain, KryptoBrain.Repo,
  adapter: Ecto.Adapters.Postgres,
  database: "krypto_brain_repo",
  username: "master",
  password: "secret",
  hostname: "localhost"

config :krypto_brain, ecto_repos: [KryptoBrain.Repo]

config :krypto_brain, KryptoBrain.Trading.Requests,
  PINK: 0,
  # pawel.duda91
  poloniex_api_key0: System.get_env("POLONIEX_API_KEY0") || "${POLONIEX_API_KEY0}",
  poloniex_api_secret0: System.get_env("POLONIEX_API_SECRET0") || "${POLONIEX_API_SECRET0}",

  EMC2: 1,
  # p.awelduda91
  poloniex_api_key1: System.get_env("POLONIEX_API_KEY1") || "${POLONIEX_API_KEY1}",
  poloniex_api_secret1: System.get_env("POLONIEX_API_SECRET1") || "${POLONIEX_API_SECRET1}",

  GNT: 2,
  # pa.welduda91
  poloniex_api_key2: System.get_env("POLONIEX_API_KEY2") || "${POLONIEX_API_KEY2}",
  poloniex_api_secret2: System.get_env("POLONIEX_API_SECRET2") || "${POLONIEX_API_SECRET2}",

  BCN: 3,
  # paw.elduda91
  poloniex_api_key3: System.get_env("POLONIEX_API_KEY3") || "${POLONIEX_API_KEY3}",
  poloniex_api_secret3: System.get_env("POLONIEX_API_SECRET3") || "${POLONIEX_API_SECRET3}"

# Useful when debugging OTP:
config :logger, handle_sasl_reports: true
config :logger, format: "[$level] $message\n",
  backends: [{LoggerFileBackend, :error_log}, :console]

config :logger, :error_log,
  path: "log/error.log",
  level: :error

# config :krypto_brain, traders: [
#   [currency_pair: "BTC_ETH", start_btc_balance: 0.008],
  # [currency_pair: "BTC_LTC", start_btc_balance: 0.008],
  # [currency_pair: "BTC_ETH", start_btc_balance: 0.008],
  # [currency_pair: "BTC_ETH", start_btc_balance: 0.008],
  # [currency_pair: "BTC_ETH", start_btc_balance: 0.008]
# ]

# This configuration is loaded before any dependency and is restricted
# to this project. If another project depends on this project, this
# file won't be loaded nor affect the parent project. For this reason,
# if you want to provide default values for your application for
# 3rd-party users, it should be done in your "mix.exs" file.

# You can configure for your application as:
#
#     config :krypto_brain, key: :value
#
# And access this configuration in your application as:
#
#     Application.get_env(:krypto_brain, :key)
#
# Or configure a 3rd-party app:
#
#     config :logger, level: :info
#

# It is also possible to import configuration files, relative to this
# directory. For example, you can emulate configuration per environment
# by uncommenting the line below and defining dev.exs, test.exs and such.
# Configuration from the imported file will override the ones defined
# here (which is why it is important to import them last).
#
#     import_config "#{Mix.env}.exs"
