defmodule Govee.Conn do
  @moduledoc """
  Struct that represents a connection to a device

  Can be backed by either a BlueHeron device or a GoveeScenic device
  """

  use TypedStruct

  typedstruct(enforce: true) do
    field :name, String.t()
    field :raw_device, any()
  end
end

defprotocol Govee.ConnBuilder do
  @doc "Build the conn for the specific raw device"
  def build(device)
end
