import gleam/bool
import gleam/erlang/process.{type Subject}
import gleam/http.{Patch, Post}
import gleam/http/request
import gleam/http/response
import gleam/httpc.{FailedToConnect, InvalidUtf8Response}
import gleam/int
import gleam/io
import gleam/option.{Some}
import gleam/otp/actor
import gleam/string
import timer_actor

pub type BooleanSensor {
  BooleanSensor(
    id: String,
    name: String,
    state: State,
    detect_boolean_timer: Subject(timer_actor.Message),
    server_addr: option.Option(ServerAddress),
  )
}

pub fn boolean_detected(p: BooleanSensor) -> Bool {
  case p.state {
    BooleanDetected -> True
    BooleanNotDetected -> False
  }
}

pub type State {
  BooleanDetected
  BooleanNotDetected
}

fn state_to_event(s: State) -> String {
  case s {
    BooleanDetected -> "boolean_detected"
    BooleanNotDetected -> "boolean_not_detected"
  }
}

pub type ServerAddress {
  ServerAddress(host: String, port: Int)
}

pub type Message {
  Register(sender: Subject(Response), server_addr: ServerAddress)
  StatusCheck(sender: Subject(Response))
  ExecuteAction(sender: Subject(Response), action_id: String)
}

pub fn register_msg(
  sender: Subject(Response),
  server_addr: ServerAddress,
) -> BooleanSensorMessage {
  timer_actor.Other(Register(sender:, server_addr:))
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

pub fn actor() -> Result(
  actor.Started(Subject(BooleanSensorMessage)),
  actor.StartError,
) {
  actor.new_with_initialiser(50, fn(self) {
    let assert Ok(detect_boolean_timer) = timer_actor.timer_actor(self)
    actor.send(detect_boolean_timer.data, timer_actor.start(5000))

    BooleanSensor(
      "ps-1",
      "boolean-sensor-1",
      BooleanNotDetected,
      detect_boolean_timer.data,
      option.None,
    )
    |> actor.initialised()
    |> actor.returning(self)
    |> Ok
  })
  |> actor.on_message(handle_message)
  |> actor.start
}

fn handle_message(
  ps: BooleanSensor,
  msg: BooleanSensorMessage,
) -> actor.Next(BooleanSensor, BooleanSensorMessage) {
  case msg {
    timer_actor.TimePassed(..) -> {
      let new_state = case int.random(4) {
        0 -> BooleanDetected
        _ -> BooleanNotDetected
      }
      case ps.server_addr {
        Some(server_address) if new_state != ps.state -> {
          let new_ps = BooleanSensor(..ps, state: new_state)
          send_state(new_ps, server_address)
          send_event(new_ps, new_ps.state, server_address)
          new_ps
        }
        _ -> ps
      }
    }
    timer_actor.Other(value) ->
      case value {
        ExecuteAction(sender:, action_id: _) -> {
          actor.send(sender, ExecuteActionResp("Action not found"))
          ps
        }
        StatusCheck(sender:) -> {
          actor.send(sender, StatusCheckResp)
          ps
        }
        Register(sender:, server_addr:) -> {
          actor.send(
            sender,
            RegisterResp(
              DeviceDescription(
                ps.id,
                ps.name,
                [
                  DevicePropertyDescription(
                    "boolean-detected",
                    "Boolean detected",
                    boolean_detected(ps),
                    None(BoolType),
                  ),
                ],
                [],
                [
                  state_to_event(BooleanDetected),
                  state_to_event(BooleanNotDetected),
                ],
              ),
            ),
          )
          BooleanSensor(..ps, server_addr: Some(server_addr))
        }
      }
  }
  |> actor.continue
}

fn send_state(ps: BooleanSensor, server_address: ServerAddress) -> Nil {
  process.spawn_unlinked(fn() {
    let assert Ok(req) =
      request.to(
        "http://"
        <> server_address.host
        <> ":"
        <> int.to_string(server_address.port)
        <> "/api/devices/"
        <> ps.id
        <> "/properties/boolean-detected",
      )

    let value =
      boolean_detected(ps)
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
  ps: BooleanSensor,
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
        <> ps.id
        <> "/events",
      )

    req
    |> request.set_method(Post)
    |> request.prepend_header("Content-Type", "application/json")
    |> request.set_body("{\"event\": \"" <> state_to_event(event) <> "\"}")
    |> httpc.send()
    |> log_failed_request()
  })
  Nil
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
