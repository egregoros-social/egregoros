defmodule Egregoros.MixProject do
  use Mix.Project

  def project do
    [
      app: :egregoros,
      version: "0.1.0",
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      test_coverage: [
        tool: Egregoros.TestCoverageTool,
        summary: [threshold: 85],
        ignore_modules: [
          EgregorosWeb.AdminHTML,
          Egregoros.Release,
          EgregorosWeb.OAuthHTML,
          EgregorosWeb.RegistrationHTML,
          EgregorosWeb.SessionHTML,
          EgregorosWeb.SettingsHTML,
          Egregoros.TestCoverageTool,
          Mix.Tasks.Egregoros.Admin,
          Mix.Tasks.Egregoros.Actors.Refetch,
          Mix.Tasks.Egregoros.Badges.Issue,
          Mix.Tasks.Egregoros.Bench.Seed,
          Mix.Tasks.Egregoros.Bench.Run,
          Mix.Tasks.Egregoros.Bench.Explain,
          Mix.Tasks.Egregoros.Vc.EnsureProofs,
          Mix.Tasks.Egregoros.Vc.MigrateDidIssuer,
          Mix.Tasks.Egregoros.Vc.Reproof,
          Egregoros.Bench.Seed
        ]
      ],
      aliases: aliases(),
      deps: deps(),
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Egregoros.Application, []},
      extra_applications: [:logger, :runtime_tools, :os_mon]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:phoenix, "~> 1.8.3"},
      {:phoenix_ecto, "~> 4.5"},
      {:ecto_sql, "~> 3.13"},
      {:ecto_psql_extras, "~> 0.7"},
      {:postgrex, ">= 0.0.0"},
      {:oban, "~> 2.19"},
      {:oban_web, "~> 2.11"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.1.0"},
      {:fast_sanitize, "~> 0.2.0"},
      {:image, "~> 0.62"},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:mox, "~> 1.1", only: :test},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.3", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.2.0",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:swoosh, "~> 1.16"},
      {:req, "~> 0.5"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 1.0"},
      {:jason, "~> 1.2"},
      {:flake_id, "~> 0.1.0"},
      {:dns_cluster, "~> 0.2.0"},
      {:bandit, "~> 1.5"},
      {:tidewave, "~> 0.5", only: :dev}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.test": ["cmd --cd assets node --test"],
      "assets.build": ["compile", "tailwind egregoros", "esbuild egregoros"],
      "assets.deploy": [
        "tailwind egregoros --minify",
        "esbuild egregoros --minify",
        "phx.digest"
      ],
      precommit: [
        "compile --warnings-as-errors",
        "deps.unlock --unused",
        "format --check-formatted",
        "assets.test",
        "test --cover"
      ]
    ]
  end
end
