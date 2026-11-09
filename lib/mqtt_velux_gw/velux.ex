defmodule MqttVeluxGw.Velux do
  @moduledoc """
  GenServer managing the KLF200 connection and forwarding Velux node
  updates to MQTT.
  """

  use GenServer
  require Logger

  alias MqttVeluxGw.Mqtt

  # Client

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def update do
    GenServer.cast(__MODULE__, :update)
  end

  # Server

  def init(_args) do
    Process.flag(:trap_exit, true)
    {:ok, nil, {:continue, :init}}
  end

  def handle_continue(:init, _state) do
    {:ok, mqtt_client_id} = Mqtt.connect()
    Mqtt.publish_meta(mqtt_client_id)

    Mqtt.publish(mqtt_client_id, "status", "ready")
    Mqtt.publish(mqtt_client_id, "last_seen", now())

    Process.send_after(self(), :connect, 0)

    {:noreply, %{mqtt_client_id: mqtt_client_id, update_interval: nil}}
  end

  def handle_info(:connect, %{mqtt_client_id: mqtt_client_id} = state) do
    %{ip: ip, password: pw, update_interval: update_interval} =
      velux_conf()

    Klf200.connect(ip, pw)
    Mqtt.publish(mqtt_client_id, "status", "online")
    Mqtt.publish(mqtt_client_id, "last_seen", now())

    Process.send_after(self(), :update, update_interval)
    {:noreply, %{state | update_interval: update_interval}}
  end

  def handle_info(:update, %{update_interval: update_interval} = state) do
    Process.send_after(self(), :update, update_interval)
    {:noreply, update_mqtt(state)}
  end

  def handle_info({{_module, _mqtt_client_id}, _ref, :ok}, state) do
    # responses from mqtt messages send with qos other than 0
    {:noreply, state}
  end

  def handle_info({:EXIT, _pid, _signal}, state) do
    {:noreply, state}
  end

  def handle_cast(:update, state) do
    {:noreply, update_mqtt(state)}
  end

  def terminate({{:badmatch, {:error, {:already_started, _pid}}}, _trace}, _state),
    do: Logger.info("Velux process already started")

  def terminate(reason, state) do
    Logger.info("Shuting down velux process: #{inspect(reason)}")
    velux_offline(state)
    :normal
  end

  defp update_mqtt(%{mqtt_client_id: mqtt_client_id} = state) do
    Enum.each(Klf200.nodes(), fn {k, v} ->
      Mqtt.publish(mqtt_client_id, k, Map.take(v, [:name, :node_type, :current_pos]))
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

  defp velux_offline(%{mqtt_client_id: mqtt_client_id}) do
    Klf200.disconnect()
    Logger.info("Velux connection lost/closed. Sending update to MQTT...")
    Mqtt.publish(mqtt_client_id, "status", "offline")
  end

  defp velux_offline(_state), do: Klf200.disconnect()

  defp now, do: DateTime.utc_now(:second) |> DateTime.to_iso8601()
end
