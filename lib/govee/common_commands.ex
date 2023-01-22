defmodule Govee.CommonCommands do
  @moduledoc """
  Common commands amongst supported govee devices
  """

  alias Govee.Command

  # @keep_alive_indicator 0xAA
  @command_indicator 0x33

  @commands %{
    power: 0x01,
    brightness: 0x04,
    color: 0x05,
    timer: 0x0B
  }

  @led_modes %{
    manual: 0x02,
    microphone: 0x06,
    scenes: 0x04
  }

  def build_binary(%Command{type: :set_color, value: rgb}) do
    use_white_leds = 0x0

    build_command_binary(
      @commands[:color],
      <<@led_modes[:manual], rgb::24, use_white_leds, rgb::24>>
    )
  end

  def build_binary(%Command{type: :set_white, value: value}) do
    use_white_leds = 0x1
    rgb = Govee.ShadesOfWhite.get_color(value)

    build_command_binary(
      @commands[:color],
      <<@led_modes[:manual], 0xFF, 0xFF, 0xFF, use_white_leds, rgb::24>>
    )
  end

  def build_binary(%Command{type: :set_brightness, value: brightness}) do
    build_command_binary(@commands[:brightness], <<brightness>>)
  end

  def build_binary(%Command{type: :turn_on}) do
    build_command_binary(@commands[:power], <<0x1>>)
  end

  def build_binary(%Command{type: :turn_off}) do
    build_command_binary(@commands[:power], <<0x0>>)
  end

  defp build_command_binary(command, payload, indicator \\ @command_indicator) do
    value = pad(<<indicator, command, payload::binary>>)
    checksum = calculate_xor(value, 0)
    <<value::binary-19, checksum::8>>
  end

  defp pad(binary) when byte_size(binary) == 19, do: binary

  defp pad(binary) do
    pad(<<binary::binary, 0>>)
  end

  defp calculate_xor(<<>>, checksum), do: checksum

  defp calculate_xor(<<x::8, rest::binary>>, checksum),
    do: calculate_xor(rest, :erlang.bxor(checksum, x))
end
