defmodule GoveeTest do
  use ExUnit.Case
  doctest Govee

  test "greets the world" do
    assert Govee.hello() == :world
  end
end
