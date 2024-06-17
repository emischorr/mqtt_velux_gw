defmodule MqttVeluxGwTest do
  use ExUnit.Case
  doctest MqttVeluxGw

  test "greets the world" do
    assert MqttVeluxGw.hello() == :world
  end
end
