defmodule Govee.H6001Bulb do
  @moduledoc """
  Sample ATT application that can control the Govee LED Light Bulb

  They can be found [here](https://www.amazon.com/MINGER-Dimmable-Changing-Equivalent-Multi-Color/dp/B07CL2RMR7/)
  """

  use GenServer
  require Logger

  alias BlueHeron.HCI.Command.ControllerAndBaseband.WriteLocalName
  alias BlueHeron.HCI.Command.LEController.SetScanEnable

  alias BlueHeron.HCI.Event.LEMeta.ConnectionComplete
  alias BlueHeron.HCI.Event.DisconnectionComplete
  alias BlueHeron.HCI.Event.LEMeta.AdvertisingReport
  alias BlueHeron.HCI.Event.LEMeta.AdvertisingReport.Device

  alias Govee.H6001Bulb

  # Sets the name of the BLE device
  @write_local_name %WriteLocalName{name: "Govee Controller"}

  @default_uart_config %{
    device: "ttyACM0",
    uart_opts: [speed: 115_200],
    init_commands: [@write_local_name]
  }

  @default_usb_config %{
    vid: 0x0A5C,
    pid: 0x21E8,
    init_commands: [@write_local_name]
  }

  @doc """
  Start a linked connection to the bulb

  ## UART

      iex> {:ok, pid} = GoveeBulb.start_link(:uart, device: "ttyACM0")
      {:ok, #PID<0.111.0>}

  ## USB

      iex> {:ok, pid} = GoveeBulb.start_link(:usb)
      {:ok, #PID<0.111.0>}
  """

  # def start_link(transport_type, config \\ %{})

  # def start_link(:uart, config) do
  #   config = struct(BlueHeronTransportUART, Map.merge(@default_uart_config, config))
  #   GenServer.start_link(__MODULE__, config, [])
  # end

  # def start_link(:usb, config) do
  #   config = struct(BlueHeronTransportUSB, Map.merge(@default_usb_config, config))
  #   GenServer.start_link(__MODULE__, config, [])
  # end

  def start_link(opts, config \\ []) do
    configuration = Keyword.fetch!(opts, :configuration)

    configuration =
      case Keyword.fetch!(opts, :type) do
        :uart -> struct(BlueHeronTransportUART, Map.merge(@default_uart_config, configuration))
        :usb -> struct(BlueHeronTransportUSB, Map.merge(@default_usb_config, configuration))
      end

    config = Keyword.put_new(config, :name, __MODULE__)
    GenServer.start_link(__MODULE__, configuration, config)
  end

  @doc """
  Set the color of the bulb.

      iex> GoveeBulb.set_color(pid, 0xFFFFFF) # full white
      :ok
      iex> GoveeBulb.set_color(pid, 0xFF0000) # full red
      :ok
      iex> GoveeBulb.set_color(pid, 0x00FF00) # full green
      :ok
      iex> GoveeBulb.set_color(pid, 0x0000FF) # full blue
      :ok
  """
  def set_color(pid, rgb) do
    GenServer.call(pid, {:set_color, rgb})
  end

  def turn_off(pid) do
    GenServer.call(pid, :turn_off)
  end

  def turn_on(pid) do
    GenServer.call(pid, :turn_on)
  end

  def set_brightness(pid, brightness) do
    GenServer.call(pid, {:set_brightness, brightness})
  end

  def set_white(pid, value) do
    GenServer.call(pid, {:set_white, value})
  end

  @impl GenServer
  def init(config) do
    # Create a context for BlueHeron to operate with
    {:ok, ctx} = BlueHeron.transport(config)

    # Subscribe to HCI and ACL events
    BlueHeron.add_event_handler(ctx)

    # Start the ATT Client (this is what we use to read/write data with)
    {:ok, conn} = BlueHeron.ATT.Client.start_link(ctx)

    {:ok, %{conn: conn, ctx: ctx, connected?: false}}
  end

  @impl GenServer

  # Sent when a transport connection is established
  def handle_info({:BLUETOOTH_EVENT_STATE, :HCI_STATE_WORKING}, state) do
    # Enable BLE Scanning. This will deliver messages to the process mailbox
    # when other devices broadcast
    BlueHeron.hci_command(state.ctx, %SetScanEnable{le_scan_enable: true})
    {:noreply, state}
  end

  # Match for the Bulb.
  def handle_info(
        {:HCI_EVENT_PACKET,
         %AdvertisingReport{devices: [%Device{address: addr, data: ["\tMinger" <> _ = data]}]}},
        state
      ) do
    Logger.info("Trying to connect to Govee LED #{inspect(addr, base: :hex)}")
    Logger.info("full data: #{inspect(data)}")
    # Attempt to create a connection with it.
    :ok = BlueHeron.ATT.Client.create_connection(state.conn, peer_address: addr)
    {:noreply, state}
  end

  # ignore other HCI Events
  def handle_info({:HCI_EVENT_PACKET, _}, state), do: {:noreply, state}

  # ignore other HCI ACL data (ATT handles this for us)
  def handle_info({:HCI_ACL_DATA_PACKET, _}, state), do: {:noreply, state}

  # Sent when create_connection/2 is complete
  def handle_info({BlueHeron.ATT.Client, conn, %ConnectionComplete{}}, %{conn: conn} = state) do
    Logger.info("Govee LED connection established")
    {:noreply, %{state | connected?: true}}
  end

  # Sent if a connection is dropped
  def handle_info({BlueHeron.ATT.Client, _, %DisconnectionComplete{reason_name: reason}}, state) do
    Logger.warn("Govee LED connection dropped: #{reason}")
    {:noreply, %{state | connected?: false}}
  end

  # Ignore other ATT data
  def handle_info({BlueHeron.ATT.Client, _, _event}, state) do
    {:noreply, state}
  end

  @impl GenServer
  # Assembles the raw RGB data into a binary that the bulb expects
  # this was found here https://github.com/Freemanium/govee_btled#analyzing-the-traffic
  def handle_call({:set_color, rgb}, _from, state) do
    run_if_connected(state, fn ->
      H6001Bulb.Commands.set_color(state.conn, rgb)
    end)
  end

  def handle_call(:turn_off, _from, state) do
    run_if_connected(state, fn ->
      H6001Bulb.Commands.turn_off(state.conn)
    end)
  end

  def handle_call(:turn_on, _from, state) do
    run_if_connected(state, fn ->
      H6001Bulb.Commands.turn_on(state.conn)
    end)
  end

  def handle_call({:set_brightness, brightness}, _from, state) do
    run_if_connected(state, fn ->
      H6001Bulb.Commands.set_brightness(state.conn, brightness)
    end)
  end

  def handle_call({:set_white, value}, _from, state) do
    run_if_connected(state, fn ->
      H6001Bulb.Commands.set_white(state.conn, value)
    end)
  end

  defp run_if_connected(state, fun) do
    if state.connected? do
      case fun.() do
        :ok ->
          {:reply, :ok, state}

        error ->
          Logger.warn("Received error: #{inspect(error)}")
          {:reply, error, state}
      end
    else
      Logger.warn("Not currently connected to a bulb")
      {:reply, {:error, :disconnected}, state}
    end
  end
end
