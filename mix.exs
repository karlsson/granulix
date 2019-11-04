defmodule Mix.Tasks.Compile.GranulixNif do
  def run(_args) do
    {result, _errcode} = System.cmd("make", [], cd: "c_src", stderr_to_stdout: true)
    Mix.Project.build_structure()
    IO.binwrite(result)
  end

  def clean() do
    {result, _errcode} = System.cmd("make", ["clean"], cd: "c_src", stderr_to_stdout: true)
    IO.binwrite(result)
  end
end

defmodule Granulix.MixProject do
  use Mix.Project

  def project do
    [
      app: :granulix,
      compilers: [:granulix_nif | Mix.compilers()],
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
      {:ex_doc, "~> 0.20.2", only: :dev, runtime: false},
      {:xalsa, "~> 0.2.0"},
      {:granulix_protocol,
       git: "https://github.com/karlsson/granulix_protocol.git"},
      {:granulix_analog_echo,
       git: "https://github.com/karlsson/granulix_analog_echo.git"}
    ]
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
