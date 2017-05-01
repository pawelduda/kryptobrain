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

      worker(KryptoBrain.Trading.Trader, ["PINK"], id: "PINK"),
      worker(KryptoBrain.Trading.Trader, ["EMC2"], id: "EMC2"),
      worker(KryptoBrain.Trading.Trader, ["GNT"], id: "GNT"),
      worker(KryptoBrain.Trading.Trader, ["BCN"], id: "BCN")
    ]

    opts = [strategy: :one_for_one, name: KryptoBrain.Supervisor, max_seconds: 100, max_restarts: 100]
    Supervisor.start_link(children, opts)
  end
end
