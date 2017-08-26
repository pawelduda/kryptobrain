defmodule KryptoBrain.Trading.SignalData do
  @enforce_keys ~w(signal retrieval_date_gmt last_price)a
  defstruct ~w(signal retrieval_date_gmt last_price last_upper_bband last_lower_bband last_stoch_rsi_k)a
end
