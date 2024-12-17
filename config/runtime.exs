import Config

config :mqtt_velux_gw, :velux,
  ip: System.get_env("VELUX_IP"),
  password: System.get_env("VELUX_PW"),
  # refresh interval in seconds
  update_interval: System.get_env("VELUX_INTERVAL") || 10

config :mqtt_velux_gw, :mqtt,
  host: System.get_env("MQTT_HOST") || "127.0.0.1",
  port: System.get_env("MQTT_PORT") || 1883,
  username: System.get_env("MQTT_USER") || nil,
  password: System.get_env("MQTT_PW") || nil,
  event_topic_namespace: System.get_env("MQTT_EVENT_TOPIC_NS") || "home/get/velux_gw",
  cmd_topic_namespace: System.get_env("MQTT_CMD_TOPIC_NS") || "home/cmd/velux_gw"
