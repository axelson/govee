defmodule Govee.BLEConnectionManager do
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

  alias Govee.Device

  defmodule State do
    use TypedStruct

    typedstruct(enforce: true) do
      field :devices, list()
      # Devices that have been seen but not configured
      field :seen_devices, list()
      field :transport_config, map()
      field :ctx, BlueHeron.Context.t()
    end
  end

  @options_schema [
    # TODO: Support lists cleanly
    # Originally nimble_options doesn't support the list type:
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
    Logger.info("genserver_opts: #{inspect(genserver_opts, pretty: true)}")
    genserver_opts = Keyword.put_new(genserver_opts, :name, __MODULE__)
    Logger.info("genserver_opts: #{inspect(genserver_opts, pretty: true)}")

    case NimbleOptions.validate(opts, @options_schema) do
      {:ok, opts} ->
        # devices = []
        devices =
         Keyword.fetch!(opts, :devices)
         |> Enum.map(&Device.new!/1)

        Logger.info("starting with devices: #{inspect(devices, pretty: true)}")

        config = %{
          devices: devices,
          transport_config: Keyword.fetch!(opts, :transport_config)
        }

        Logger.warn("Govee BLEConnectionManager start_link with opts: #{inspect(opts)}")

        Logger.warn(
          "Govee BLEConnectionManager start_link with genserver_opts: #{inspect(genserver_opts)}"
        )

        Logger.warn("Govee BLEConnectionManager start_link with config: #{inspect(config)}")

        GenServer.start_link(__MODULE__, config, genserver_opts)

      {:error, error} ->
        Logger.warn("Options did not validate. Full options were: #{inspect(opts)}")
        raise error
    end
  end

  def connected_devices(pid) do
    GenServer.call(pid, :connected_devices)
  end

  def add_device(pid, device) do
    GenServer.call(pid, {:add_device, device})
  end

  def remove_device(pid, device_addr) do
    GenServer.call(pid, {:remove_device, device_addr})
  end

  def execute_command(pid, command, device) do
    GenServer.call(pid, {:execute_command, command, device})
  end

  @impl GenServer
  def init(config) do
    Logger.info("BLEConnectionManager starting with config: #{inspect(config)}")

    # # Temporary hack until I figure out how to set the name from the child_spec thing
    # try do
    #   true = Process.register(self(), BLEServer)
    # rescue
    #   e in ArgumentError ->
    #     Logger.error("Unable to register name: #{inspect(e)}")
    # end

    # Create a context for BlueHeron to operate with
    Logger.info("BLEConnectionManager transport config: #{inspect(config.transport_config)}")
    {:ok, ctx} = BlueHeron.transport(config.transport_config)
    Logger.info("built context: #{inspect(ctx)}")

    # Subscribe to HCI and ACL events
    BlueHeron.add_event_handler(ctx)

    # Start the ATT Client for each device
    devices =
      Enum.map(config.devices, fn device ->
        Logger.info("Starting ATT Client")
        {:ok, pid} = BlueHeron.ATT.Client.start_link(ctx)
        %Device{device | att_client: pid}
      end)

    Logger.info("devices: #{inspect(devices)}")

    state = struct(State, Map.merge(config, %{devices: devices, ctx: ctx, seen_devices: []}))

    Logger.info("#{__MODULE__} initialized with state: #{inspect(state, pretty: true)}")
    {:ok, state}
  end

  # Sent when a transport connection is established
  @impl GenServer
  def handle_info({:BLUETOOTH_EVENT_STATE, :HCI_STATE_WORKING}, state) do
    Logger.info("Got HCI_STATE_WORKING")
    # Enable BLE Scanning. This will deliver messages to the process mailbox
    # when other devices broadcast
    BlueHeron.hci_command(state.ctx, %SetScanEnable{le_scan_enable: true})
    {:noreply, state}
  end

  def handle_info({:HCI_EVENT_PACKET, %AdvertisingReport{} = advertising_report}, state) do
    matched_devices =
      Enum.flat_map(state.devices, fn device ->
        if Device.matches_advertising_packet?(device, advertising_report) do
          Logger.info(
            "Creating ATT Client connection for #{Device.pretty_name(device)} #{inspect(device.addr, base: :hex)}"
          )

          connect_device!(device)

          [Device.mark_connecting(device)]
        else
          # if Enum.random(1..1000) <= 2 || true do
          #   # Logger.info("Saw device: #{inspect(type)} with addr: #{inspect(addr)}")
          #   Logger.info("Ignoring device that doesn't match advertising packet")
          #   Logger.info("advertising_report: #{inspect(advertising_report, pretty: true)}")
          # end

          []
        end
      end)

    state =
      if Enum.empty?(matched_devices) do
        case Device.parse_advertising_packet(advertising_report) do
          {:ok, {type, addr}} ->
            if Enum.random(1..1000) <= 2 do
              Logger.info("Saw device: #{inspect(type)} with addr: #{inspect(addr)}")
            end

            update_seen_devices(state, Device.new!(type: type, addr: addr))

          {:error, :unrecognized_device} ->
            # if Enum.random(1..100) >= 8 do
            #   Logger.info(
            #     "Ignoring unrecognized device #{inspect(advertising_report, pretty: true)}"
            #   )
            # end

            state
        end
      else
        updated_devices =
          Enum.map(state.devices, fn device ->
            Enum.find(matched_devices, device, &(&1.addr == device.addr))
          end)

        Logger.info("updated_devices: #{inspect(updated_devices, pretty: true)}")
        %State{state | devices: updated_devices}
      end

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
        {BlueHeron.ATT.Client, att_client, %ConnectionComplete{status: status}},
        state
      ) do
    Logger.info("Connection complete for other status")
    Logger.info("status: #{inspect(status, pretty: true)}")

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
  def handle_info({BlueHeron.ATT.Client, _, event}, state) do
    Logger.info("ATT Client event #{inspect(event)}")
    {:noreply, state}
  end

  @impl GenServer
  def handle_call(:get_conns, _from, state) do
    conns =
      Enum.map(state.devices, fn device ->
        Govee.ConnBuilder.build(device)
        # %ToReplace.Conn{
        #   # FIXME: HACKS!
        #   name: to_string(device.addr) |> String.to_atom(),
        #   driver_pid: nil,
        #   view_port_name: :main_hopefully_not_used,
        #   topic: :some_topic,
        #   device: device
        # }
      end)

    {:reply, conns, state}
  end

  def handle_call(:connected_devices, _from, state) do
    devices = Enum.filter(state.devices, fn device -> device.connection_status == :connected end)
    {:reply, devices, state}
  end

  def handle_call({:add_device, device_opts}, _from, %State{} = state) do
    Logger.info("adding device!")
    device_opts = Keyword.validate!(device_opts, [:type, :addr])
    addr = Keyword.fetch!(device_opts, :addr)

    # if device already added then return an error
    if Enum.any?(state.devices, &(&1.addr == addr)) do
      {:reply, {:error, :device_already_added}, state}
    else
      device = Device.new!(device_opts)
      Logger.info("Starting ATT Client for #{inspect(device)}")
      {:ok, pid} = BlueHeron.ATT.Client.start_link(state.ctx)
      seen_devices = Enum.filter(state.seen_devices, &(&1 != device))
      device = %Device{device | att_client: pid}

      state = %State{state | devices: [device | state.devices], seen_devices: seen_devices}

      {:reply, {:ok, device}, state}
    end
  end

  def handle_call({:remove_device, device_addr}, _from, state) do
    case Enum.find(state.devices, &(&1.addr == device_addr)) do
      nil ->
        {:reply, {:error, :device_not_known}, state}

      %Device{connection_status: :connected} = device ->
        case disconnect_device(device) do
          :ok ->
            Logger.info(
              "Disconnected device: #{Device.pretty_name(device)} #{inspect(device.addr, base: :hex)}"
            )

            new_devices = Enum.filter(state.devices, &(&1.addr != device_addr))
            Logger.info("new_devices: #{inspect(new_devices, pretty: true)}")
            state = %State{state | devices: new_devices}
            {:reply, :ok, state}

          error ->
            {:reply, {:error, error}, state}
        end

      _ ->
        {:reply, {:error, :device_not_connected}, state}
    end
  end

  def handle_call({:execute_command, command, device}, _from, state) do
    result =
      Govee.ExecuteCommands.execute_command(device.att_client, command)
      |> tap(fn res ->
        Logger.info("res: #{inspect(res, pretty: true)}")
      end)

    {:reply, result, state}
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

    Logger.info("with att client devices: #{inspect(devices, pretty: true)}")
    %State{state | devices: devices}
  end

  defp update_seen_devices(%State{} = state, device) do
    if Enum.any?(state.seen_devices, &Device.eql(&1, device)) do
      state
    else
      %State{state | seen_devices: [device | state.seen_devices]}
    end
  end

  defp connect_device!(%Device{} = device) do
    :ok =
      BlueHeron.ATT.Client.create_connection(device.att_client,
        peer_address: device.addr.integer
      )
  end

  defp disconnect_device(%Device{} = device) do
    BlueHeron.ATT.Client.disconnect(device.att_client,
      peer_address: device.addr.integer
    )
  end
end
