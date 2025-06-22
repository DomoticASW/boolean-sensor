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

pub type PresenceSensor {
  PresenceSensor(
    id: String,
    name: String,
    state: State,
    detect_presence_timer: Subject(timer_actor.Message),
    server_addr: option.Option(ServerAddress),
  )
}

pub fn presence_detected(p: PresenceSensor) -> Bool {
  case p.state {
    PresenceDetected -> True
    PresenceNotDetected -> False
  }
}

pub type State {
  PresenceDetected
  PresenceNotDetected
}

fn state_to_event(s: State) -> String {
  case s {
    PresenceDetected -> "presence_detected"
    PresenceNotDetected -> "presence_not_detected"
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
) -> PresenceSensorMessage {
  timer_actor.Other(Register(sender:, server_addr:))
}

pub fn status_check_msg(sender: Subject(Response)) -> PresenceSensorMessage {
  timer_actor.Other(StatusCheck(sender:))
}

pub type PresenceSensorMessage =
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
  actor.Started(Subject(PresenceSensorMessage)),
  actor.StartError,
) {
  actor.new_with_initialiser(50, fn(self) {
    let assert Ok(detect_presence_timer) = timer_actor.timer_actor(self)
    actor.send(detect_presence_timer.data, timer_actor.start(5000))

    PresenceSensor(
      "ps-1",
      "presence-sensor-1",
      PresenceNotDetected,
      detect_presence_timer.data,
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
  ps: PresenceSensor,
  msg: PresenceSensorMessage,
) -> actor.Next(PresenceSensor, PresenceSensorMessage) {
  case msg {
    timer_actor.TimePassed(..) -> {
      let new_state = case int.random(4) {
        0 -> PresenceDetected
        _ -> PresenceNotDetected
      }
      case ps.server_addr {
        Some(server_address) if new_state != ps.state -> {
          let new_ps = PresenceSensor(..ps, state: new_state)
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
                    "presence-detected",
                    "Presence detected",
                    presence_detected(ps),
                    None(BoolType),
                  ),
                ],
                [],
                [
                  state_to_event(PresenceDetected),
                  state_to_event(PresenceNotDetected),
                ],
              ),
            ),
          )
          PresenceSensor(..ps, server_addr: Some(server_addr))
        }
      }
  }
  |> actor.continue
}

fn send_state(ps: PresenceSensor, server_address: ServerAddress) -> Nil {
  process.spawn_unlinked(fn() {
    let assert Ok(req) =
      request.to(
        "http://"
        <> server_address.host
        <> ":"
        <> int.to_string(server_address.port)
        <> "/api/devices/"
        <> ps.id
        <> "/properties/presence-detected",
      )

    let value =
      presence_detected(ps)
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
  ps: PresenceSensor,
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
