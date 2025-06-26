import gleam/bool
import gleam/bytes_tree
import gleam/erlang/process.{type Subject}
import gleam/http.{Patch, Post}
import gleam/http/request
import gleam/http/response
import gleam/httpc.{FailedToConnect, InvalidUtf8Response}
import gleam/int
import gleam/io
import gleam/json
import gleam/option.{type Option, Some}
import gleam/otp/actor
import gleam/string
import timer_actor
import udp

pub type BooleanSensor {
  BooleanSensor(
    id: String,
    name: String,
    target_condition: Condition,
    condition_probability: Probability,
    condition_test_period_ms: Int,
    server_address: option.Option(ServerAddress),
    socket: option.Option(udp.Socket),
    state: State,
    timer_check_condition: Subject(timer_actor.Message),
    timer_announce: Subject(timer_actor.Message),
  )
}

pub type Condition =
  String

type State =
  Bool

pub opaque type Probability {
  Probability(p: Int)
}

pub fn new_probability(p: Int) -> Result(Probability, Nil) {
  case p >= 0 && p <= 100 {
    True -> Ok(Probability(p:))
    False -> Error(Nil)
  }
}

fn state_to_event(s: State, target_condition: Condition) -> String {
  case s {
    True -> target_condition <> " detected"
    False -> target_condition <> " not detected"
  }
}

fn property_id(s: BooleanSensor) -> String {
  s.target_condition |> string.lowercase() <> "-detected"
}

pub type ServerAddress {
  ServerAddress(host: String, port: Int)
}

pub type Message {
  Register(sender: Subject(Response), server_address: ServerAddress)
  StatusCheck(sender: Subject(Response))
  ExecuteAction(sender: Subject(Response), action_id: String)
}

pub fn register_msg(
  sender: Subject(Response),
  server_address: ServerAddress,
) -> BooleanSensorMessage {
  timer_actor.Other(Register(sender:, server_address:))
}

pub fn status_check_msg(sender: Subject(Response)) -> BooleanSensorMessage {
  timer_actor.Other(StatusCheck(sender:))
}

pub type BooleanSensorMessage =
  timer_actor.TimePassed(Message)

pub type Never

pub type DeviceDescription {
  DeviceDescription(
    id: String,
    name: String,
    properties: List(DevicePropertyDescription),
    actions: List(Never),
    events: List(String),
  )
}

pub type DevicePropertyDescription {
  DevicePropertyDescription(
    id: String,
    name: String,
    value: Bool,
    // To be updated if the device complexity grows
    type_constraints: TypeConstraintsDescription,
  )
}

pub type Types {
  BoolType
}

pub type TypeConstraintsDescription {
  None(type_: Types)
}

pub type Response {
  RegisterResp(device_description: DeviceDescription)
  StatusCheckResp
  ExecuteActionResp(error: String)
}

pub fn actor(
  id id: String,
  name name: String,
  target_condition target_condition: String,
  condition_probability condition_probability: Probability,
  condition_test_period_ms condition_test_period_ms: Int,
  server_address server_address: Option(ServerAddress),
) -> Result(actor.Started(Subject(BooleanSensorMessage)), actor.StartError) {
  actor.new_with_initialiser(50, fn(self) {
    let assert Ok(timer_check_condition) = timer_actor.timer_actor(self)
    actor.send(timer_check_condition.data, timer_actor.start(5000))

    let assert Ok(timer_announce) = timer_actor.timer_actor(self)
    actor.send(timer_announce.data, timer_actor.start(1000))

    BooleanSensor(
      id:,
      name:,
      target_condition:,
      condition_probability:,
      condition_test_period_ms:,
      timer_check_condition: timer_check_condition.data,
      timer_announce: timer_announce.data,
      state: False,
      server_address:,
      socket: option.None,
    )
    |> actor.initialised()
    |> actor.returning(self)
    |> Ok
  })
  |> actor.on_message(handle_message)
  |> actor.start
}

fn handle_message(
  s: BooleanSensor,
  msg: BooleanSensorMessage,
) -> actor.Next(BooleanSensor, BooleanSensorMessage) {
  case msg {
    timer_actor.TimePassed(sender:, ..) if sender == s.timer_check_condition -> {
      let new_state = int.random(101) <= s.condition_probability.p
      case s.server_address {
        Some(server_address) if new_state != s.state -> {
          let new_s = BooleanSensor(..s, state: new_state)
          send_state(new_s, server_address)
          send_event(new_s, new_s.state, server_address)
          new_s
        }
        _ -> s
      }
    }
    timer_actor.TimePassed(..) -> {
      case s.server_address, s.socket {
        option.None, option.None -> {
          let assert Ok(socket) = udp.open(0, [])
          send_udp_announce(socket, #(255, 255, 255, 255), 30_000, s)
          BooleanSensor(..s, socket: Some(socket))
        }
        option.None, Some(socket) -> {
          send_udp_announce(socket, #(255, 255, 255, 255), 30_000, s)
          s
        }
        Some(_), Some(socket) -> {
          udp.close(socket)
          s
        }
        Some(_), option.None -> s
      }
    }
    timer_actor.Other(value) ->
      case value {
        ExecuteAction(sender:, action_id: _) -> {
          actor.send(sender, ExecuteActionResp("Action not found"))
          s
        }
        StatusCheck(sender:) -> {
          actor.send(sender, StatusCheckResp)
          s
        }
        Register(sender:, server_address:) -> {
          actor.send(
            sender,
            RegisterResp(
              DeviceDescription(
                s.id,
                s.name,
                [
                  DevicePropertyDescription(
                    property_id(s),
                    s.target_condition <> " detected",
                    s.state,
                    None(BoolType),
                  ),
                ],
                [],
                [
                  state_to_event(True, s.target_condition),
                  state_to_event(False, s.target_condition),
                ],
              ),
            ),
          )
          BooleanSensor(..s, server_address: Some(server_address))
        }
      }
  }
  |> actor.continue
}

fn send_state(s: BooleanSensor, server_address: ServerAddress) -> Nil {
  process.spawn_unlinked(fn() {
    let assert Ok(req) =
      request.to(
        "http://"
        <> server_address.host
        <> ":"
        <> int.to_string(server_address.port)
        <> "/api/devices/"
        <> s.id
        <> "/properties/"
        <> property_id(s),
      )

    let value =
      s.state
      |> bool.to_string
      |> string.lowercase

    req
    |> request.set_method(Patch)
    |> request.prepend_header("Content-Type", "application/json")
    |> request.set_body("{\"value\": " <> value <> "}")
    |> httpc.send()
    |> log_failed_request()
  })
  Nil
}

fn send_event(
  s: BooleanSensor,
  event: State,
  server_address: ServerAddress,
) -> Nil {
  process.spawn_unlinked(fn() {
    let assert Ok(req) =
      request.to(
        "http://"
        <> server_address.host
        <> ":"
        <> int.to_string(server_address.port)
        <> "/api/devices/"
        <> s.id
        <> "/events",
      )

    req
    |> request.set_method(Post)
    |> request.prepend_header("Content-Type", "application/json")
    |> request.set_body(
      "{\"event\": \"" <> state_to_event(event, s.target_condition) <> "\"}",
    )
    |> httpc.send()
    |> log_failed_request()
  })
  Nil
}

fn send_udp_announce(
  socket: udp.Socket,
  addr: udp.Address,
  port: Int,
  s: BooleanSensor,
) -> Nil {
  case
    json.object([
      #("id", json.string(s.id)),
      #("name", json.string(s.name)),
      #("port", json.int(8080)),
    ])
    |> json.to_string_tree
    |> bytes_tree.from_string_tree
    |> udp.send(socket, addr, port, _)
  {
    Error(_) -> io.println_error("Something went wrong sending udp announce")
    Ok(_) -> Nil
  }
}

fn log_failed_request(
  res: Result(response.Response(String), httpc.HttpError),
) -> Nil {
  case res {
    Error(InvalidUtf8Response) -> io.println_error("Invalid UTF8 reponse")
    Error(FailedToConnect(_, _)) -> io.println_error("Failed to connect")
    Ok(res) if res.status >= 200 && res.status < 300 -> Nil
    Ok(res) ->
      { "Error in response " <> int.to_string(res.status) <> " " <> res.body }
      |> io.println_error
  }
}
