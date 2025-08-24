import boolean_sensor_actor.{
  type Condition, type Probability, type ServerAddress, ServerAddress,
} as bs_actor
import envoy
import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/io
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import mist
import router
import wisp
import wisp/wisp_mist

type Configuration {
  Configuration(
    id: String,
    name: String,
    target_condition: Condition,
    condition_probability: Probability,
    condition_test_period_ms: Int,
    server_address: Option(ServerAddress),
    port: Int,
    discovery_broadcast_addr: String,
    server_discovery_port: Int,
    lan_hostname: String,
  )
}

fn parse_condition_probability(
  default default: Probability,
) -> Result(Probability, String) {
  case envoy.get("CONDITION_PROBABILITY") {
    Error(_) -> Ok(default)
    Ok(s) ->
      int.parse(s)
      |> result.then(bs_actor.new_probability)
      |> result.map_error(fn(_) { "Given probability " <> s <> " is not valid" })
  }
}

fn parse_condition_test_period_ms(default default: Int) -> Result(Int, String) {
  case envoy.get("CONDITION_TEST_PERIOD_MS") {
    Error(_) -> Ok(default)
    Ok(s) -> {
      int.parse(s)
      |> result.map_error(fn(_) { "Given period " <> s <> " is not valid" })
      |> result.then(fn(p) {
        case p <= 0 {
          True -> Error("Period must be > 0")
          False -> Ok(p)
        }
      })
    }
  }
}

fn parse_port(default default: Int) -> Result(Int, String) {
  case envoy.get("PORT") {
    Error(_) -> Ok(default)
    Ok(s) -> {
      int.parse(s)
      |> result.map_error(fn(_) { "Given port " <> s <> " is not valid" })
    }
  }
}

fn parse_server_address(
  default default: Option(ServerAddress),
) -> Result(Option(ServerAddress), String) {
  case envoy.get("SERVER_ADDRESS") {
    Error(_) -> Ok(default)
    Ok(server_address_str) -> {
      case server_address_str |> string.split(":") {
        [] | [_] | [_, _, _, ..] -> Error("Invalid server address")
        [host, port] ->
          case int.parse(port) {
            Error(_) -> Error("Invalid server address port")
            Ok(port) -> Ok(Some(ServerAddress(host:, port:)))
          }
      }
    }
  }
}

fn parse_server_discovery_port() -> Result(Int, String) {
  let env_var = "SERVER_DISCOVERY_PORT"
  envoy.get(env_var)
  |> result.map_error(fn(_) {
    "Missing value for required env var: " <> env_var
  })
  |> result.try(fn(s) {
    int.parse(s)
    |> result.map_error(fn(_) { "Given port " <> s <> " is not valid" })
  })
}

fn parse_lan_hostname() -> Result(String, String) {
  let env_var = "LAN_HOSTNAME"
  envoy.get(env_var)
  |> result.map_error(fn(_) {
    "Missing value for required env var: " <> env_var
  })
}

fn parse_configuration(
  def_id id: String,
  def_target_condition target_condition: Condition,
  def_condition_probability condition_probability: Probability,
  def_condition_test_period_ms condition_test_period_ms: Int,
  def_server_address server_address: Option(ServerAddress),
  def_port port: Int,
  def_discovery_broadcast_addr def_discovery_broadcast_addr: String,
) -> Result(Configuration, String) {
  let id = envoy.get("ID") |> result.unwrap(id)
  let target_condition =
    envoy.get("TARGET_CONDITION") |> result.unwrap(target_condition)
  let name = envoy.get("NAME") |> result.unwrap(target_condition <> " sensor")
  let discovery_broadcast_addr =
    envoy.get("DISCOVERY_BROADCAST_ADDR")
    |> result.unwrap(def_discovery_broadcast_addr)
  use condition_probability <- result.try(parse_condition_probability(
    default: condition_probability,
  ))
  use condition_test_period_ms <- result.try(parse_condition_test_period_ms(
    default: condition_test_period_ms,
  ))
  use server_address <- result.try(parse_server_address(default: server_address))
  use port <- result.try(parse_port(default: port))
  use server_discovery_port <- result.try(parse_server_discovery_port())
  use lan_hostname <- result.try(parse_lan_hostname())
  Ok(Configuration(
    id:,
    name:,
    target_condition:,
    condition_probability:,
    condition_test_period_ms:,
    server_address:,
    port:,
    discovery_broadcast_addr:,
    server_discovery_port:,
    lan_hostname:,
  ))
}

fn start_boolean_sensor_actor(
  config: Configuration,
) -> Result(Subject(bs_actor.BooleanSensorMessage), String) {
  bs_actor.actor(
    id: config.id,
    name: config.name,
    target_condition: config.target_condition,
    condition_probability: config.condition_probability,
    condition_test_period_ms: config.condition_test_period_ms,
    server_address: config.server_address,
    device_port: config.port,
    server_discovery_port: config.server_discovery_port,
    discovery_broadcast_addr: config.discovery_broadcast_addr,
    lan_hostname: config.lan_hostname,
  )
  |> result.map(fn(a) { a.data })
  |> result.map_error(fn(_) {
    "Something went wrong while starting boolean sensor actor"
  })
}

fn start_wisp(
  bs_subj: Subject(bs_actor.BooleanSensorMessage),
  config: Configuration,
) -> Result(Nil, String) {
  mist.new(fn(req) {
    let assert Ok(client_ip_addr) =
      mist.get_client_info(req.body)
      |> result.map(fn(info) { mist.ip_address_to_string(info.ip_address) })
    wisp_mist.handler(
      router.handle_request(_, client_ip_addr, bs_subj),
      wisp.random_string(64),
    )(req)
  })
  |> mist.bind("0.0.0.0")
  |> mist.port(config.port)
  |> mist.start()
  |> result.map(fn(_) { Nil })
  |> result.map_error(fn(_) { "Something went wrong while starting web server" })
}

pub fn main() -> Nil {
  case
    {
      use config <- result.try(parse_configuration(
        def_id: "boolean-sensor",
        def_target_condition: "Presence",
        def_condition_probability: {
          let assert Ok(p) = bs_actor.new_probability(25)
          p
        },
        def_condition_test_period_ms: 5000,
        def_server_address: None,
        def_port: 8080,
        def_discovery_broadcast_addr: "255.255.255.255",
      ))
      use bs_actor <- result.try(start_boolean_sensor_actor(config))
      wisp.configure_logger()
      start_wisp(bs_actor, config)
    }
  {
    Error(msg) -> io.println_error(msg)
    Ok(_) -> process.sleep_forever()
  }
}
