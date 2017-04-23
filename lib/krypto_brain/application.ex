defmodule KryptoBrain.Application do
  @moduledoc false

  use Application
  require KryptoBrain.Constants
  alias KryptoBrain.Constants, as: C

  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    children = [
      # supervisor(KryptoBrain.Repo, []),
      worker(KryptoBrain.Trading.StateHolder, []),
      worker(KryptoBrain.Trading.NonceGenerator, []),

      worker(KryptoBrain.Trading.Trader, ["DGB", 0.0, C._ALT], id: "DGB"),
      worker(KryptoBrain.Trading.Trader, ["XEM", 0.012, C._BTC], id: "XEM"),
      worker(KryptoBrain.Trading.Trader, ["MAID", 0.0, C._ALT], id: "MAID"),
      worker(KryptoBrain.Trading.Trader, ["PINK", 0.012, C._BTC], id: "PINK")
    ]

    opts = [strategy: :one_for_one, name: KryptoBrain.Supervisor, max_seconds: 100, max_restarts: 100]
    Supervisor.start_link(children, opts)
  end
end
