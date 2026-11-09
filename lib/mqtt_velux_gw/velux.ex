defmodule MqttVeluxGw.Velux do
  @moduledoc """
  GenServer managing the KLF200 connection and forwarding Velux node
  updates to MQTT.

  All access to the KLF200 goes through this process so that requests are
  serialized (the KLF200 client can only track one waiting caller at a time).
  Failures (timeouts, crashed client) trigger a reconnect with backoff
  instead of crashing.
  """

  use GenServer
  require Logger

  alias MqttVeluxGw.Mqtt

  @min_backoff 5_000
  @max_backoff 60_000

  # Client

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def update do
    GenServer.cast(__MODULE__, :update)
  end

  @doc "Set the position (0 = open, 100 = closed) of a node. Non-blocking."
  def position(node, pos) when is_integer(node) and is_integer(pos) do
    GenServer.cast(__MODULE__, {:position, node, pos})
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

    send(self(), :connect)

    {:noreply,
     %{
       mqtt_client_id: mqtt_client_id,
       update_interval: nil,
       update_timer: nil,
       klf_pid: nil,
       backoff: @min_backoff,
       pending: []
     }}
  end

  def handle_info(:connect, %{mqtt_client_id: mqtt_client_id} = state) do
    %{ip: ip, password: pw, update_interval: update_interval} = velux_conf()
    state = %{state | update_interval: update_interval}

    case safe_klf(fn -> Klf200.connect(ip, pw) end) do
      {:ok, _} ->
        klf_pid = Process.whereis(Klf200.Client)
        Logger.info("Connected to KLF200 at #{ip}")
        Mqtt.publish(mqtt_client_id, "status", "online")
        Mqtt.publish(mqtt_client_id, "last_seen", now())

        state =
          %{state | klf_pid: klf_pid, backoff: @min_backoff}
          |> replay_pending()
          |> schedule_update()

        {:noreply, state}

      {:error, reason} ->
        Logger.warning("Connecting to KLF200 failed: #{inspect(reason)}")
        {:noreply, reconnect(state)}
    end
  end

  def handle_info(:update, %{klf_pid: nil} = state), do: {:noreply, state}

  def handle_info(:update, state) do
    {:noreply, state |> update_mqtt() |> schedule_update()}
  end

  def handle_info({{_module, _mqtt_client_id}, _ref, :ok}, state) do
    # responses from mqtt messages send with qos other than 0
    {:noreply, state}
  end

  def handle_info({:EXIT, pid, reason}, %{klf_pid: pid} = state) when is_pid(pid) do
    Logger.warning("KLF200 client exited: #{inspect(reason)}")
    {:noreply, reconnect(%{state | klf_pid: nil})}
  end

  def handle_info({:EXIT, _pid, _signal}, state) do
    {:noreply, state}
  end

  def handle_cast(:update, %{klf_pid: nil} = state), do: {:noreply, state}

  def handle_cast(:update, state) do
    {:noreply, update_mqtt(state)}
  end

  def handle_cast({:position, node, pos}, %{klf_pid: nil} = state) do
    Logger.info("KLF200 not connected; queuing position #{pos} for node #{node}")
    {:noreply, %{state | pending: state.pending ++ [{node, pos}]}}
  end

  def handle_cast({:position, node, pos}, state) do
    case send_position(node, pos) do
      :ok ->
        {:noreply, state}

      {:retry, reason} ->
        Logger.warning(
          "Position #{pos} for node #{node} failed (#{inspect(reason)}); retrying after reconnect"
        )

        {:noreply, reconnect(%{state | pending: state.pending ++ [{node, pos}]})}
    end
  end

  def terminate({{:badmatch, {:error, {:already_started, _pid}}}, _trace}, _state),
    do: Logger.info("Velux process already started")

  def terminate(reason, state) do
    Logger.info("Shuting down velux process: #{inspect(reason)}")
    velux_offline(state)
    :normal
  end

  # Sends a position command. Returns :ok when done (or not worth retrying)
  # and {:retry, reason} when the KLF200 connection seems broken.
  defp send_position(node, pos) do
    case safe_klf(fn -> Klf200.position(node, pos) end) do
      {:ok, {:error, reason}} ->
        Logger.warning("Position #{pos} for node #{node} rejected: #{inspect(reason)}")
        :ok

      {:ok, _} ->
        :ok

      {:error, reason} ->
        {:retry, reason}
    end
  end

  defp replay_pending(%{pending: []} = state), do: state

  defp replay_pending(%{pending: pending} = state) do
    Enum.each(pending, fn {node, pos} ->
      case send_position(node, pos) do
        :ok ->
          :ok

        {:retry, reason} ->
          Logger.error("Dropping position #{pos} for node #{node}: #{inspect(reason)}")
      end
    end)

    %{state | pending: []}
  end

  defp update_mqtt(%{mqtt_client_id: mqtt_client_id} = state) do
    case safe_klf(&Klf200.nodes/0) do
      {:ok, nodes} when is_map(nodes) ->
        Enum.each(nodes, fn {k, v} ->
          Mqtt.publish(mqtt_client_id, k, Map.take(v, [:name, :node_type, :current_pos]))
        end)

        state

      other ->
        Logger.warning("Fetching KLF200 nodes failed: #{inspect(other)}")
        reconnect(state)
    end
  end

  # Tears down the current KLF200 client (if any) and schedules a new
  # connection attempt with exponential backoff.
  defp reconnect(state) do
    state = cancel_update(state)
    Mqtt.publish(state.mqtt_client_id, "status", "offline")

    case Process.whereis(Klf200.Client) do
      nil ->
        :ok

      pid ->
        # unlink first so the client's death doesn't trigger another reconnect
        Process.unlink(pid)
        safe_klf(&Klf200.disconnect/0)
        Process.exit(pid, :kill)
    end

    Logger.info("Reconnecting to KLF200 in #{div(state.backoff, 1000)}s")
    Process.send_after(self(), :connect, state.backoff)

    %{state | klf_pid: nil, backoff: min(state.backoff * 2, @max_backoff)}
  end

  defp schedule_update(state) do
    state = cancel_update(state)
    %{state | update_timer: Process.send_after(self(), :update, state.update_interval)}
  end

  defp cancel_update(%{update_timer: nil} = state), do: state

  defp cancel_update(%{update_timer: ref} = state) do
    Process.cancel_timer(ref)
    %{state | update_timer: nil}
  end

  # Runs a KLF200 call, converting exits (timeouts, dead process) and raised
  # errors (failed matches in Klf200.connect/2) into {:error, reason}.
  defp safe_klf(fun) do
    {:ok, fun.()}
  catch
    :exit, reason -> {:error, reason}
    :error, reason -> {:error, reason}
  end

  defp velux_conf do
    [ip: ip, password: pw, update_interval: update_interval] =
      Application.get_env(:mqtt_velux_gw, :velux)

    interval =
      case update_interval do
        string when is_binary(string) ->
          case Integer.parse(string) do
            {int, _} -> int
            :error -> 10
          end

        int when is_integer(int) ->
          int

        _else ->
          10
      end

    %{ip: ip, password: pw, update_interval: max(interval, 1) * 1000}
  end

  defp velux_offline(%{mqtt_client_id: mqtt_client_id}) do
    safe_klf(&Klf200.disconnect/0)
    Logger.info("Velux connection lost/closed. Sending update to MQTT...")
    Mqtt.publish(mqtt_client_id, "status", "offline")
  end

  defp velux_offline(_state), do: safe_klf(&Klf200.disconnect/0)

  defp now, do: DateTime.utc_now(:second) |> DateTime.to_iso8601()
end
