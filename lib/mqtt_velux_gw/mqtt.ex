defmodule MqttVeluxGw.Mqtt do
  def client(), do: "velux_gw_#{Enum.random(1..9)}"

  def connect(), do: connect(client())
  def connect(client_id) do
    config = Application.get_env(:mqtt_velux_gw, :mqtt)

    case Tortoise.Supervisor.start_child(
      client_id: client_id,
      handler: {Tortoise.Handler.Logger, []},
      server: {Tortoise.Transport.Tcp, host: config[:host], port: config[:port]},
      user_name: config[:username], password: config[:password]
    ) do
      {:ok, _pid} -> {:ok, client_id}
      {:error, reason} -> {:error, reason}
    end
  end

  def publish(client_id, day, key, value) do
    Tortoise.publish(client_id, "home/get/velux_gw/#{day}/#{key}", value, [qos: 0, retain: true])
  end
end
