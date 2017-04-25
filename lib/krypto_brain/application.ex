defmodule KryptoBrain.Application do
  @moduledoc false

  use Application
  require KryptoBrain.Constants
  alias KryptoBrain.Constants, as: C

  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    children = [
      # supervisor(KryptoBrain.Repo, []),
      # worker(KryptoBrain.Trading.StateHolder, []),
      # worker(KryptoBrain.Trading.NonceGenerator, []),

      worker(KryptoBrain.Trading.Trader, ["DGB"], id: "DGB"),
      worker(KryptoBrain.Trading.Trader, ["ETH"], id: "ETH"),
      worker(KryptoBrain.Trading.Trader, ["DOGE"], id: "DOGE"),
      worker(KryptoBrain.Trading.Trader, ["VIA"], id: "VIA")
    ]

    opts = [strategy: :one_for_one, name: KryptoBrain.Supervisor, max_seconds: 100, max_restarts: 100]
    Supervisor.start_link(children, opts)
  end
end
