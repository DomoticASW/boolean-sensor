# A boolean sensor simulated device for testing DomoticASW

This sensor is highly customizable and aims to be able to emulate any sensor which can detect a condition or its absence

## Run with docker

```sh
docker run ventus218/domoticasw-boolean-sensor
```

The following configurations can be passed to the container as environment variables.

For example `docker run -e TARGET="Rain" ventus218/domoticasw-boolean-sensor`

| Variable name            | Default value              | Explanation                                           | Admissible values               |
| ------------------------ | -------------------------- | ----------------------------------------------------- | ------------------------------- |
| ID                       | boolean-sensor             | Device id                                             | Any string unique in the system |
| NAME                     | \<TARGET_CONDITION> sensor | Sensor name                                           | Any string                      |
| TARGET_CONDITION         | Presence                   | Name/Kind of the condition to detect                  | Any string                      |
| CONDITION_PROBABILITY    | 25                         | Probability of the condition to happen                | Integer >= 0 and <= 100         |
| CONDITION_TEST_PERIOD_MS | 5000                       | Amount of time between two subsequent measures (ms)   | Integer > 0                    |
| SERVER_ADDRESS           |                            | Should be set if boolean sensor is already registered | \<host>:\<port>                 |
| PORT                     | 8080                       | Port on which the device will listen                  | Any valid port                  |
