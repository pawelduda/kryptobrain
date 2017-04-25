defmodule KryptoBrain.Mixfile do
  use Mix.Project

  def project do
    [app: :krypto_brain,
     version: "0.1.0",
     elixir: "~> 1.4",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     deps: deps()]
  end

  # Configuration for the OTP application
  #
  # Type "mix help compile.app" for more information
  def application do
    # Specify extra applications you'll use from Erlang/Elixir
    [extra_applications: [:logger, :spell, :ecto, :postgrex, :httpoison, :timex, :calendar],
     mod: {KryptoBrain.Application, []}]
  end

  # Dependencies can be Hex packages:
  #
  #   {:my_dep, "~> 0.3.0"}
  #
  # Or git/path repositories:
  #
  #   {:my_dep, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
  #
  # Type "mix help deps" for more examples and options
  defp deps do
    [
      {:spell, github: "Zatvobor/spell", ref: "5f055dcc4b8b15c55dbc6f1f20c54fc4ebfbfe25"},
      {:httpoison, "~> 0.11.1"},
      {:poison, "~> 3.0", override: true},
      {:postgrex, ">= 0.0.0"},
      {:ecto, "~> 2.1"},
      {:export, "~> 0.1.0"},
      {:calendar, "~> 0.16.1"},
      {:timex, "~> 3.0"},
      {:logger_file_backend, "0.0.4"}
    ]
  end
end
