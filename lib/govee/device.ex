defmodule Govee.Device do
  use TypedStruct
  require Logger
  alias BlueHeron.HCI.Event.LEMeta.AdvertisingReport

  typedstruct(enforce: true) do
    field :type, atom()
    field :addr, integer()
    field :connection_status, :disconnected | :connecting | :connected, default: :disconnected
    field :att_client, pid(), default: nil
  end

  @options_schema [
    type: [
      required: true,
      type: {:in, [:h6001, :h6159, :h5074]}
    ],
    addr: [
      required: true,
      type: :non_neg_integer
    ]
  ]
  def new!(opts) do
    case NimbleOptions.validate(opts, @options_schema) do
      {:ok, opts} ->
        addr = Keyword.fetch!(opts, :addr)

        %__MODULE__{
          type: Keyword.fetch!(opts, :type),
          addr: BlueHeron.Address.parse(addr)
        }

      {:error, error} ->
        Logger.warn("Options did not validate. Full options were: #{inspect(opts)}")
        raise error
    end
  end

  def eql(%__MODULE__{} = a, %__MODULE__{} = b) do
    a.type == b.type && a.addr == b.addr
  end

  @doc """
  Mostly for use with scenic
  """
  def random_addr do
    Enum.random(0..0xFFFFFFFFFFFF)
  end

  def parse_advertising_packet(%AdvertisingReport{} = advertising_report) do
    case advertising_report do
      %AdvertisingReport{
        devices: [%AdvertisingReport.Device{address: address, data: ["\tMinger" <> _]}]
      } ->
        {:ok, {:h6001, address}}

      %AdvertisingReport{
        devices: [%AdvertisingReport.Device{address: address, data: ["\tihoment_H6159" <> _]}]
      } ->
        {:ok, {:h6159, address}}

      %AdvertisingReport{
        devices: [%AdvertisingReport.Device{address: address, data: ["\tGovee_H5074" <> _]}]
      } ->
        {:ok, {:h5074, address}}

      _ ->
        {:error, :unrecognized_device}
    end
  end

  def matches_advertising_packet?(
        %__MODULE__{type: type, addr: addr},
        %AdvertisingReport{} = advertising_report
      ) do
    case parse_advertising_packet(advertising_report) do
      {:ok, {^type, ^addr}} -> true
      {:ok, {^type, advertised_addr}} -> advertised_addr == addr.integer
      _other -> false
    end
  end

  def mark_connecting(%__MODULE__{} = device) do
    %__MODULE__{device | connection_status: :connecting}
  end

  def mark_connected(%__MODULE__{} = device) do
    %__MODULE__{device | connection_status: :connected}
  end

  def mark_disconnected(%__MODULE__{} = device) do
    %__MODULE__{device | connection_status: :disconnected}
  end

  def pretty_name(%__MODULE__{type: :h6001}), do: "H6001 Govee Bulb"
  def pretty_name(%__MODULE__{type: :h6159}), do: "H6159 Govee LED Strip"
  def pretty_name(%__MODULE__{type: :h5074}), do: "H5074 Temperature/Humidity Sensor"
  def pretty_name(%__MODULE__{type: _}), do: "Unknown device type"

  def debug_log_name(%__MODULE__{} = device) do
    [pretty_name(device), " ", to_string(device.addr)]
  end
end

defmodule ToReplace.Conn do
  use TypedStruct

  typedstruct enforce: true do
    field :driver_pid, pid()
    # Name has to be an atom because of scenic
    field :name, atom()
    # ViewPort name has to be an atom because of scenic
    field :view_port_name, atom()
    # Topic doesn't really have to be an atom
    field :topic, atom()
    # Do we really need this?
    field :device, Govee.Device.t()
  end
end

defimpl Govee.ConnBuilder, for: Govee.Device do
  def build(device) do
    %Govee.Conn{
      name: to_string(device.addr),
      raw_device: device
    }
  end
end
