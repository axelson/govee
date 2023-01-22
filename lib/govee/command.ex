defmodule Govee.Command do
  use TypedStruct
  @type command() :: :set_color | :set_white | :set_brightness | :turn_on | :turn_off

  alias Govee.Command

  typedstruct enforce: true do
    field :type, command()
    field :value, any(), enforce: false
  end

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
  def set_color(rgb) when is_integer(rgb) do
    %Command{
      type: :set_color,
      value: rgb
    }
  end

  @doc """
  The Govee H6001 bulb has a different set of LED's for pure white, the rgb
  value is partially ignored
  """
  def set_white(value) when -1 <= value and value <= 1 do
    %Command{
      type: :set_white,
      value: value
    }
  end

  @doc """
  Set the brightness using a scale from 0 to 255
  """
  def set_brightness(brightness) when 0 <= brightness and brightness < 256 do
    %Command{
      type: :set_brightness,
      value: brightness
    }
  end

  @doc """
  Turn on the bulb
  """
  def turn_on do
    %Command{
      type: :turn_on
    }
  end

  @doc """
  Turn off the bulb
  """
  def turn_off do
    %Command{
      type: :turn_off
    }
  end
end
