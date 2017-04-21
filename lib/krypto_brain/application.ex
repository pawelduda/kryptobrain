defmodule KryptoBrain.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    children = [
      supervisor(KryptoBrain.Repo, []),

      worker(KryptoBrain.Trading.Trader, ["BTC_ETH", 0.008], id: 1),
      # worker(KryptoBrain.Trading.Trader, ["BTC_LTC", 0.008], id: 2),
      # worker(KryptoBrain.Trading.Trader, ["BTC_DASH", 0.008], id: 3),
      # worker(KryptoBrain.Trading.Trader, ["BTC_BELA", 0.008], id: 4)
    ]

    opts = [strategy: :one_for_one, name: KryptoBrain.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
