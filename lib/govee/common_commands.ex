defmodule Govee.CommonCommands do
  @moduledoc """
  Common commands amongst supported govee devices
  """

  @keep_alive_indicator 0xAA
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

  @doc """
  Set the color of the bulb.

      iex> GoveeBulb.set_color(conn, 0xFFFFFF) # full white
      :ok
      iex> GoveeBulb.set_color(conn, 0xFF0000) # full red
      :ok
      iex> GoveeBulb.set_color(conn, 0x00FF00) # full green
      :ok
      iex> GoveeBulb.set_color(conn, 0x0000FF) # full blue
      :ok
  """
  def set_color(rgb) do
    use_white_leds = 0x0

    build_command_binary(
      @commands[:color],
      <<@led_modes[:manual], rgb::24, use_white_leds, rgb::24>>
    )
  end

  @doc """
  The Govee H6001 bulb has a different set of LED's for pure white, the rgb
  value is partially ignored
  """
  def set_white(rgb) do
    use_white_leds = 0x1

    build_command_binary(
      @commands[:color],
      <<@led_modes[:manual], 0xFF, 0xFF, 0xFF, use_white_leds, rgb::24>>
    )
  end

  @doc """
  Set the brightness using a scale from 0 to 255
  """
  def set_brightness(brightness) when brightness >= 0 and brightness < 256 do
    build_command_binary(@commands[:brightness], <<brightness>>)
  end

  @doc """
  Turn on the bulb
  """
  def turn_on do
    build_command_binary(@commands[:power], <<0x1>>)
  end

  @doc """
  Turn off the bulb
  """
  def turn_off do
    build_command_binary(@commands[:power], <<0x0>>)
  end

  def build_command_binary(command, payload, indicator \\ @command_indicator) do
    value = pad(<<indicator, command, payload::binary>>)
    checksum = calculate_xor(value, 0)
    <<value::binary-19, checksum::8>>
  end

  def send_command(command, conn) do
    handle = 0x0015
    BlueHeron.ATT.Client.write(conn, handle, command)
  end

  defp pad(binary) when byte_size(binary) == 19, do: binary

  defp pad(binary) do
    pad(<<binary::binary, 0>>)
  end

  defp calculate_xor(<<>>, checksum), do: checksum

  defp calculate_xor(<<x::8, rest::binary>>, checksum),
    do: calculate_xor(rest, :erlang.bxor(checksum, x))
end
