defmodule Govee.CommandExecutor do
  @callback execute_command(any(), Govee.Command.t()) :: any()
end
