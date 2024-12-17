defmodule MqttVeluxGw.Velux do
  use GenServer
  require Logger

  alias MqttVeluxGw.Mqtt

  # Client

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def refresh do
    GenServer.call(__MODULE__, :refresh)
  end

  # Server

  def init(_args) do
    Process.flag(:trap_exit, true)
    {:ok, nil, {:continue, :init}}
  end

  def handle_continue(:init, _state) do
    {:ok, mqtt_client_id} = Mqtt.connect()
    Mqtt.publish_meta(mqtt_client_id)

    %{ip: ip, password: pw, update_interval: update_interval} =
      velux_conf()

    Klf200.connect(ip, pw)
    Mqtt.publish(mqtt_client_id, "status", "online")
    Mqtt.publish(mqtt_client_id, "last_seen", now())

    Process.send_after(self(), :update, update_interval)

    {:noreply,
     %{
       mqtt_client_id: mqtt_client_id,
       update_interval: update_interval
     }}
  end

  def handle_info(:update, state) do
    Process.send_after(self(), :update, state.update_interval)
    {:noreply, update_mqtt(state)}
  end

  def handle_info({{_module, _mqtt_client_id}, _ref, :ok}, state) do
    # responses from mqtt messages send with qos other than 0
    {:noreply, state}
  end

  def handle_info({:EXIT, _pid, _signal}, state) do
    {:noreply, state}
  end

  def terminate(reason, state) do
    Logger.info("Shuting down velux process: #{inspect(reason)}")
    send_velux_offline(state)
    :normal
  end

  defp update_mqtt(state) do
    Enum.each(Klf200.nodes(), fn {k, v} ->
      Mqtt.publish(state.mqtt_client_id, k, Map.take(v, [:name, :node_type, :current_pos]))
    end)

    state
  end

  defp velux_conf do
    [ip: ip, password: pw, update_interval: update_interval] =
      Application.get_env(:mqtt_velux_gw, :velux)

    interval =
      case update_interval do
        string when is_binary(string) -> Integer.parse(string)
        int when is_integer(int) -> int
        _else -> 10
      end

    %{ip: ip, password: pw, update_interval: max(interval, 1) * 1000}
  end

  defp send_velux_offline(%{mqtt_client_id: mqtt_client_id}) do
    Logger.info("Velux connection lost")
    Mqtt.publish(mqtt_client_id, "status", "offline")
  end

  defp now, do: DateTime.utc_now(:second) |> DateTime.to_iso8601()
end
