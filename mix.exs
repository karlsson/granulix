defmodule Granulix.MixProject do
  use Mix.Project

  def project do
    [
      app: :granulix,
      make_cwd: "c_src",
      make_clean: ["clean"],
      compilers: [:elixir_make] ++ Mix.compilers(),
      version: "0.1.0",
      elixir: "~> 1.9",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      # Docs
      name: "Granulix",
      source_url: "https://github.com/karlsson/granulix",
      docs: [
        main: "Granulix",
        extras: ["README.md"]
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :xalsa],
      env: [
        backend_api: Xalsa
      ]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ex_doc, "~> 0.22", only: :dev, runtime: false},
      {:elixir_make, "~> 0.6", runtime: false}
    ]
    ++ deps(:git)
  end

  defp deps(:hex) do
    [{:xalsa, "~> 0.3.0"},
     {:sc_plugin_nifs, git: "https://github.com/karlsson/sc_plugin_nifs.git"}]
  end
  defp deps(:git) do
    [{:xalsa, git: "https://github.com/karlsson/xalsa.git"},
     {:sc_plugin_nifs, git: "https://github.com/karlsson/sc_plugin_nifs.git"}]
  end
  defp deps(:path) do
    [{:xalsa, path: "../xalsa"},
     {:sc_plugin_nifs, path: "../sc_plugin_nifs"}]
  end
  defp description do
     "Synthesizing software using NIF generators and filters."
  end

  defp package do
    [
      maintainers: ["Mikael Karlsson"],
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => "https://github.com/karlsson/granulix"}
    ]
  end
end
