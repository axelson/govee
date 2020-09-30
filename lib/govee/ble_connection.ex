defmodule Govee.BLEConnection do
  @moduledoc """
  GenServer to manage the BlueHeron BLE connection and ATT Client's to support
  multiple devices
  """

  use GenServer
  require Logger

  alias BlueHeron.HCI.Command.LEController.SetScanEnable
  alias BlueHeron.HCI.Event.DisconnectionComplete
  alias BlueHeron.HCI.Event.LEMeta.AdvertisingReport
  alias BlueHeron.HCI.Event.LEMeta.ConnectionComplete

  alias Govee.BLEConnection.Device

  defmodule State do
    use TypedStruct

    typedstruct(enforce: true) do
      field :devices, list()
      field :transport_config, map()
      field :ctx, BlueHeron.Context.t()
    end
  end

  @options_schema [
    # nimble_options doesn't support the list type:
    # https://github.com/dashbitco/nimble_options/issues/28
    devices: [
      type: :any,
      required: true
    ],
    transport_config: [
      required: true,
      # TODO: Enforce %BlueHeronTransportUART{} or %BlueHeronTransportUSB{}
      type: :any
    ]
  ]
  def start_link(opts, genserver_opts \\ []) do
    case NimbleOptions.validate(opts, @options_schema) do
      {:ok, opts} ->
        devices =
          Keyword.fetch!(opts, :devices)
          |> Enum.map(&Device.new/1)

        config = %{
          devices: devices,
          transport_config: Keyword.fetch!(opts, :transport_config)
        }

        GenServer.start_link(__MODULE__, config, genserver_opts)

      {:error, error} ->
        Logger.warn("Options did not validate. Full options were: #{inspect(opts)}")
        raise error
    end
  end

  def connected_devices(pid) do
    GenServer.call(pid, :connected_devices)
  end

  @impl GenServer
  def init(config) do
    # Temporary hack until I figure out how to set the name from the child_spec thing
    true = Process.register(self(), Server)

    # Create a context for BlueHeron to operate with
    {:ok, ctx} = BlueHeron.transport(config.transport_config)

    # Subscribe to HCI and ACL events
    BlueHeron.add_event_handler(ctx)

    # Start the ATT Client for each device
    devices =
      Enum.map(config.devices, fn device ->
        {:ok, pid} = BlueHeron.ATT.Client.start_link(ctx)
        %Device{device | att_client: pid}
      end)

    state = struct(State, Map.merge(config, %{devices: devices, ctx: ctx}))

    {:ok, state}
  end

  # Sent when a transport connection is established
  @impl GenServer
  def handle_info({:BLUETOOTH_EVENT_STATE, :HCI_STATE_WORKING}, state) do
    # Enable BLE Scanning. This will deliver messages to the process mailbox
    # when other devices broadcast
    BlueHeron.hci_command(state.ctx, %SetScanEnable{le_scan_enable: true})
    {:noreply, state}
  end

  def handle_info({:HCI_EVENT_PACKET, %AdvertisingReport{} = advertising_report}, state) do
    Enum.each(state.devices, fn device ->
      if Device.matches_advertising_packet?(device, advertising_report) do
        Logger.info(
          "Starting connection for #{Device.pretty_name(device)} #{
            inspect(device.addr, base: :hex)
          }"
        )

        :ok = BlueHeron.ATT.Client.create_connection(device.att_client, peer_address: device.addr.integer)
      end
    end)

    {:noreply, state}
  end

  # ignore other HCI Events
  def handle_info({:HCI_EVENT_PACKET, _}, state), do: {:noreply, state}

  # ignore other HCI ACL data (ATT handles this for us)
  def handle_info({:HCI_ACL_DATA_PACKET, _}, state), do: {:noreply, state}

  # Sent when create_connection/2 is complete
  def handle_info(
        {BlueHeron.ATT.Client, att_client, %ConnectionComplete{status: 0}},
        state
      ) do
    state =
      with_device_by_att_client(state, att_client, fn device ->
        Logger.info(["Govee connection established for ", Device.debug_log_name(device)])
        Device.mark_connected(device)
      end)

    {:noreply, state}
  end

  def handle_info(
        {BlueHeron.ATT.Client, att_client, %DisconnectionComplete{reason_name: reason}},
        state
      ) do
    Logger.warn("Govee connection dropped: #{reason}")

    state =
      with_device_by_att_client(state, att_client, fn device ->
        Device.mark_disconnected(device)
      end)

    {:noreply, state}
  end

  # Ignore other ATT data
  def handle_info({BlueHeron.ATT.Client, _, _event}, state) do
    # Logger.info("ATT Client event #{inspect(event)}")
    {:noreply, state}
  end

  @impl GenServer
  def handle_call(:connected_devices, _from, state) do
    devices = Enum.filter(state.devices, fn device -> device.connected? end)
    {:reply, devices, state}
  end

  defp with_device_by_att_client(state, att_client, fun) when is_function(fun, 1) do
    devices =
      Enum.map(state.devices, fn device ->
        if device.att_client == att_client do
          fun.(device)
        else
          device
        end
      end)

    %State{state | devices: devices}
  end
end
