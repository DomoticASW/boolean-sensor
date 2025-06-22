import envoy
import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/io
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import mist
import presence_sensor_actor as ps_actor
import router
import wisp
import wisp/wisp_mist

type Configuration {
  Configuration(
    id: String,
    name: String,
    server_address: Option(ServerAddress),
    port: Int,
  )
}

type ServerAddress {
  ServerAddress(host: String, port: Int)
}

fn parse_port(default default: Int) -> Result(Int, String) {
  case envoy.get("PORT") {
    Error(_) -> Ok(default)
    Ok(port_str) -> {
      int.parse(port_str)
      |> result.map_error(fn(_) {
        "Given port " <> port_str <> " is not a valid port"
      })
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

fn parse_configuration(
  def_id id: String,
  def_name name: String,
  def_server_address server_address: Option(ServerAddress),
  def_port port: Int,
) -> Result(Configuration, String) {
  let id = envoy.get("ID") |> result.unwrap(id)
  let name = envoy.get("NAME") |> result.unwrap(name)
  use server_address <- result.try(parse_server_address(default: server_address))
  use port <- result.try(parse_port(default: port))
  Ok(Configuration(id:, name:, server_address:, port:))
}

fn start_presence_sensor_actor() -> Result(
  Subject(ps_actor.PresenceSensorMessage),
  String,
) {
  ps_actor.actor()
  |> result.map(fn(a) { a.data })
  |> result.map_error(fn(_) {
    "Something went wrong while starting presence sensor actor"
  })
}

fn start_wisp(
  ps_subj: Subject(ps_actor.PresenceSensorMessage),
  config: Configuration,
) -> Result(Nil, String) {
  wisp_mist.handler(router.handle_request(_, ps_subj), wisp.random_string(64))
  |> mist.new
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
        def_id: "ps-1",
        def_name: "Presence sensor 1",
        def_server_address: None,
        def_port: 8080,
      ))
      use ps_actor <- result.try(start_presence_sensor_actor())
      wisp.configure_logger()
      start_wisp(ps_actor, config)
    }
  {
    Error(msg) -> io.println_error(msg)
    Ok(_) -> process.sleep_forever()
  }
}
