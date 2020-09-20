# Scratch pad for new commands
defmodule Govee.MiscScratchCommands do
  @keep_alive_indicator 0xAA

  @commands %{
    power: 0x01,
    brightness: 0x04,
    color: 0x05,
    timer: 0x0B
  }

  @led_modes %{
    manual: 0x02,
    microphone: 0x06,
    scenes: 0x04
  }

  def request_state(conn) do
    # Request
    # 0000   02 0f 00 1b 00 17 00 04 00 52 15 00 aa 07 03 00
    # 0010   00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 ae

    # Write Manual Color Red
    # 0000   02 09 00 1b 00 17 00 04 00 52 15 00 33 05 02 ff
    # 0010   00 00 00 d6 e1 ff 00 00 00 00 00 00 00 00 00 03

    build_command_binary(0x07, <<0x03>>, @keep_alive_indicator)
    |> send_command(conn)
  end

  def req_color(conn) do
    # Actual Request
    # 0000   02 12 00 1b 00 17 00 04 00 52 15 00 aa 05 01 00
    # 0010   00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 ae

    # My Request
    # 0000   02 40 00 1b 00 17 00 04 00 52 15 00 aa 05 01 00
    # 0010   00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 ae

    # Response
    # 0000   02 12 20 1b 00 17 00 04 00 1b 11 00 aa 05 02 b0
    # 0010   ff 00 00 ff ea d3 00 00 00 00 00 00 00 00 00 24
    build_command_binary(@commands[:color], <<0x01>>, @keep_alive_indicator)
    |> send_command(conn)
  end

  # def gatt(conn) do
    # Actual
    # 0000   02 16 00 0b 00 07 00 04 00 10 01 00 ff ff 00 28

    # BlueHeron.ATT.Client.write(conn, %ATT.ReadByGroupTypeRequest.AttributeData{handle: <<uuid::binary-128>>}, <<1, 2, 3, 4>>)

    # This isn't quite right
    #   BlueHeron.ATT.Client.write(conn, %ATT.ReadByGroupTypeRequest{handle: 0x2800

    #           ending_handle: 65535,
    #           opcode: 16,
    #           starting_handle: 1,
    #         }, <<1, 2, 3, 4>>)
  # end

  def req_version(conn) do
    # 0000   02 14 00 1b 00 17 00 04 00 52 15 00 aa 06 00 00
    # 0010   00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 ac
    #
    # 0000   02 14 00 1b 00 17 00 04 00 52 15 00 aa 01 00 00
    # 0010   00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 ab

    # Actual
    # 0000   02 40 00 1b 00 17 00 04 00 52 15 00 aa 06 00 00
    # 0010   00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 ac
    #
    # 0000   02 40 00 1b 00 17 00 04 00 52 15 00 aa 01 01 00
    # 0010   00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 aa

    :ok =
      build_command_binary(0x06, <<0x00>>, @keep_alive_indicator)
      |> send_command(conn)

    :ok =
      build_command_binary(0x01, <<0x0>>, @keep_alive_indicator)
      |> send_command(conn)
  end

  # This command works but I need to check that it works with both bulb and led strip
  def timer(conn, minutes) when is_integer(minutes) and minutes > 0 do
    build_command_binary(
      @commands[:timer],
      <<0x01, 0x00, minutes>>
    )
    |> send_command(conn)
  end

  # I can't remember if twinkle works with the strip or the bulb
  def twinkle(conn) do
    # # twinkle
    # 33 05 04 08 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 3a

    # Red
    # 33 05 02 FF 00 00 00 FF AE 54 00 00 00 00 00 00 00 00 00 CC

    # Keep alive
    # AA 01 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 AB

    # # red
    # 33 05 02 ff 00 00 00 d6 e1 ff 00 00 00 00 00 00 00 00 00 03

    build_command_binary(
      @commands[:color],
      <<@led_modes[:scenes], 0x08>>
    )
    |> send_command(conn)
  end

  def keep_alive(conn) do
    build_command_binary(
      0xAA,
      <<0x01>>,
      @keep_alive_indicator
    )
    |> send_command(conn)
  end

  # Notes relating to `contrib/wireshark-gatt.png`
  # In which I was trying to get the govee bulb to report the current color to me
  #
  # From connor
  # so unfold the very bottom message.
  # then you can right click it -> copy -> as escaped string
  # then you can just use `BlueHeron.acl/2`
  # when it's longer than a certain amount of characters, it splits the value
  # into a few strings, so you may have to massage it in a text editor
  #
  # you can also highlight a bunch of packets that you want to replay, then go
  # file->export specified packets and then use BlueHeron.BTSnoop.decode_file to
  # turn it into something you can playback from elixir
  #
  # anything stateful like LE connections won't work obviously, but you can hack
  # it up by just mapping over the packets and replacing the LE handle

  defdelegate build_command_binary(command, payload), to: Govee.CommonCommands
  defdelegate build_command_binary(command, payload, indicator), to: Govee.CommonCommands
  defdelegate send_command(command, conn), to: Govee.CommonCommands
end
