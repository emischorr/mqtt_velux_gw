# Mqtt-Velux-Gw

A gateway service written in Elixir connecting the proprietary binary protocol of a VELUX KLF-200 GW to MQTT and vice versa.
The project pulls data from the API every 60s and publishes it to the configured MQTT broker. The topics can be adjusted via environment.
In the other direction the gateway service subscribes to MQTT topics and listens for commands and forwards them to the VELUX GW.

Tested with a VELUX KLF-200 GW.
This project is not associated with Velux.

## Docker Setup

The following command will pull the latest docker image and start the service in the background.
Ensure that you have replaced or set the environment variables accordingly.

```bash
docker run -d \
-e MQTT_HOST=$MQTT_HOST \
-e MQTT_USER=$MQTT_USER \
-e MQTT_PW=$MQTT_PW \
emischorr/mqtt_velux_gw:latest
```

You can also use the docker-compose file.

## Topics

These are examples of topics used to publish the values that are configured as default:
- 'home/get/velux_gw/window_1/status'
- ...

If you would like to use different topics you can define another namespace with the environment variable `MQTT_EVENT_TOPIC_NS`.
This defaults to 'home/get/velux_gw'.

For controlling the Velux devices one can use the following topics:
- 'home/set/velux_gw/window_1/position'

As payload use just raw/binary data.

Here you can change the namespace of these topics with the environment variable `MQTT_CMD_TOPIC_NS`.
This defaults to 'home/set/velux_gw'.