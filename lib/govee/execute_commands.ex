defmodule Govee.ExecuteCommands do
  @moduledoc """
  Executes `%Govee.Command{}` commands
  """

  @behaviour Govee.CommandExecutor

  require Logger

  @doc """
  Executes a `%Govee.Command{}` struct on a `BlueHeron` connection
  """
  def execute_command(conn, command) do
    Logger.info("Govee ExecuteCommands conn: #{inspect(conn, pretty: true)}")
    handle = 0x0015
    binary = Govee.CommonCommands.build_binary(command)
    BlueHeron.ATT.Client.write(conn, handle, binary)
  end
end
