# A presence sensor simulated device for testing DomoticASW

## Run with docker

```sh
docker run ventus218/domoticasw-presence-sensor
```

The following configurations can be passed to the container as environment variables.

For example `docker run -e NAME="Kitchen presence sensor" ventus218/domoticasw-presence-sensor`

| Variable name  | Default value     | Explanation                                            | Admissible values               |
| -------------- | ----------------- | ------------------------------------------------------ | ------------------------------- |
| ID             | ps-1              | Device id                                              | Any string unique in the system |
| NAME           | Presence sensor 1 | Sensor name                                            | Any string                      |
| SERVER_ADDRESS |                   | Should be set if presence sensor is already registered | <host>:<port>                   |
| PORT           | 8080              | Port on which the device will listen                   | Any valid port                  |
