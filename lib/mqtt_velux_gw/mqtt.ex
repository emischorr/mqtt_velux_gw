defmodule MqttVeluxGw.Mqtt do
  def client(), do: "velux_gw_#{Enum.random(1..9)}"

  def connect(), do: connect(client())

  def connect(client_id) do
    config = Application.get_env(:mqtt_velux_gw, :mqtt)

    case Tortoise311.Supervisor.start_child(
           client_id: client_id,
           handler: {MqttVeluxGw.Mqtt.Handler, []},
           server: {Tortoise311.Transport.Tcp, host: config[:host], port: config[:port]},
           user_name: config[:username],
           password: config[:password],
           subscriptions: [{"#{config[:cmd_topic_namespace]}/#", 0}],
           will: %Tortoise311.Package.Publish{
             topic: "#{config[:event_topic_namespace]}/status",
             payload: "offline",
             qos: 1,
             retain: true
           }
         ) do
      {:ok, _pid} -> {:ok, client_id}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec publish_meta(String.t()) :: :ok | {:error, :unknown_connection} | {:ok, reference}
  def publish_meta(client_id) do
    topic_ns = Application.get_env(:mqtt_velux_gw, :mqtt)[:event_topic_namespace]

    Tortoise311.publish(client_id, "#{topic_ns}/status", "online", qos: 0, retain: true)
  end

  def publish(client_id, node_key, node) when is_map(node) do
    config = Application.get_env(:mqtt_velux_gw, :mqtt)

    Enum.each(node, fn {k, v} ->
      Tortoise311.publish(
        client_id,
        "#{config[:event_topic_namespace]}/#{node_key}/#{k}",
        to_string(v),
        qos: 0,
        retain: true
      )
    end)
  end

  def publish(client_id, key, value) do
    config = Application.get_env(:mqtt_velux_gw, :mqtt)

    Tortoise311.publish(client_id, "#{config[:event_topic_namespace]}/#{key}", value,
      qos: 0,
      retain: true
    )
  end
end
