defmodule Govee.MixProject do
  use Mix.Project

  def project do
    [
      app: :govee,
      version: "0.1.0",
      elixir: "~> 1.10",
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp aliases do
    []
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:typed_struct, "~> 0.2.1"},
      {:nimble_options, "~> 0.3.0"},
      dep(:blue_heron, :github)
    ]
  end

  defp dep(:blue_heron, :hex), do: {:blue_heron, ">= 0.0.0"}

  defp dep(:blue_heron, :github),
    do: {:blue_heron, github: "blue-heron/blue_heron", branch: "main", override: true}

  defp dep(:blue_heron, :path),
    do: {:blue_heron, path: "~/dev/forks/blue_heron/blue_heron", override: true}

  defp dep(:blue_heron_transport_usb, :hex), do: {:blue_heron_transport_usb, ">= 0.0.0", only: :dev}

  defp dep(:blue_heron_transport_usb, :github),
    do:
      {:blue_heron_transport_usb,
       github: "blue-heron/blue_heron_transport_usb", branch: "main", only: :dev, override: true}

  defp dep(:blue_heron_transport_usb, :path),
    do: {:blue_heron_transport_usb, path: "~/dev/forks/blue_heron/blue_heron_transport_usb", only: :dev, override: true}
end
