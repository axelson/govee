defmodule Govee do
  @moduledoc """
  Documentation for `Govee`.
  """

  def run do
    alias BlueHeron.HCI.Command.ControllerAndBaseband.WriteLocalName

    opts = [
      devices: [
        [
          type: :h6001,
          addr: 0xA4C138EC49BD
        ],
        [
          type: :h6159,
          addr: 0xA4C138668E6F
        ]
      ],
      transport_config: %BlueHeronTransportUSB{
        vid: 0x0A5C,
        pid: 0x21E8,
        init_commands: [%WriteLocalName{name: "Govee Controller"}]
      }
    ]

    Govee.BLEConnection.start_link(opts, name: Server)
  end
end
