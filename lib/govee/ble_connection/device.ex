defmodule Govee.BLEConnection.Device do
  use TypedStruct
  require Logger
  alias BlueHeron.HCI.Event.LEMeta.AdvertisingReport

  typedstruct(enforce: true) do
    field :type, atom()
    field :addr, integer()
    field :connected?, boolean(), default: false
    field :att_client, pid(), default: nil
  end

  @options_schema [
    type: [
      required: true,
      type: {:in, [:h6001, :h6159]}
    ],
    addr: [
      required: true,
      type: :non_neg_integer
    ]
  ]
  def new(opts) do
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

  def matches_advertising_packet?(
        %__MODULE__{type: :h6001, addr: addr},
        %AdvertisingReport{} = advertising_report
      ) do
    address = addr.integer
    case advertising_report do
      %AdvertisingReport{
        devices: [%AdvertisingReport.Device{address: ^address, data: ["\tMinger" <> _]}]
      } ->
        true

      _ ->
        false
    end
  end

  def matches_advertising_packet?(
        %__MODULE__{type: :h6159, addr: addr},
        %AdvertisingReport{} = advertising_report
      ) do
    address = addr.integer
    case advertising_report do
      %AdvertisingReport{
        devices: [%AdvertisingReport.Device{address: ^address, data: ["\tihoment_H6159" <> _]}]
      } ->
        true

      _ ->
        false
    end
  end

  def mark_connected(%__MODULE__{} = device) do
    %__MODULE__{device | connected?: true}
  end

  def mark_disconnected(%__MODULE__{} = device) do
    %__MODULE__{device | connected?: false}
  end

  def pretty_name(%__MODULE__{type: :h6001}), do: "H6001 Govee Bulb"
  def pretty_name(%__MODULE__{type: :h6159}), do: "H6159 Govee LED Strip"

  def debug_log_name(%__MODULE__{} = device) do
    [pretty_name(device), " ", to_string(device.addr)]
  end
end
