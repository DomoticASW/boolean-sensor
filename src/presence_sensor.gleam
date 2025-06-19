import gleam/bool
import gleam/erlang/process.{type Subject}
import gleam/http/request
import gleam/httpc.{FailedToConnect, InvalidUtf8Response}
import gleam/int
import gleam/io
import gleam/option.{None, Some}
import gleam/otp/actor
import gleam/string
import timer_actor

pub type PresenceSensor {
  PresenceSensor(
    id: String,
    name: String,
    state: State,
    loop_timer: Subject(timer_actor.Message),
    random_detect_presence: Subject(timer_actor.Message),
    server_addr: option.Option(ServerAddress),
  )
}

pub type State {
  PresenceDetected
  PresenceNotDetected
}

pub type ServerAddress {
  ServerAddress(host: String, port: Int)
}

pub type Message {
  Register(sender: Subject(Response), server_addr: ServerAddress)
  StatusCheck(sender: Subject(Response))
  ExecuteAction(sender: Subject(Response), action_id: String)
}

pub type Description {
  Description
}

pub type Response {
  RegisterResp(description: Description)
  StatusCheckResp
  ExecuteActionResp(error: String)
}

pub fn actor() -> Result(
  actor.Started(Subject(timer_actor.TimePassed(Message))),
  actor.StartError,
) {
  actor.new_with_initialiser(50, fn(self) {
    let assert Ok(loop_timer) = timer_actor.timer_actor(self)
    actor.send(loop_timer.data, timer_actor.start(50))
    let assert Ok(detect_presence_timer) = timer_actor.timer_actor(self)
    actor.send(detect_presence_timer.data, timer_actor.start(5000))

    PresenceSensor(
      "ps-1",
      "presence-sensor-1",
      PresenceNotDetected,
      loop_timer.data,
      detect_presence_timer.data,
      None,
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
  msg: timer_actor.TimePassed(Message),
) -> actor.Next(PresenceSensor, timer_actor.TimePassed(Message)) {
  case msg {
    timer_actor.TimePassed(sender: timer, ..) if timer == ps.loop_timer ->
      case int.random(5) {
        0 -> PresenceSensor(..ps, state: PresenceDetected)
        _ -> PresenceSensor(..ps, state: PresenceNotDetected)
      }
      |> actor.continue
    timer_actor.TimePassed(..) ->
      case ps.server_addr {
        None -> ps
        Some(ServerAddress(host:, port:)) -> {
          send_state(ps, host, port)
          ps
        }
      }
      |> actor.continue
    timer_actor.Other(value) ->
      case value {
        ExecuteAction(sender:, action_id: _) -> {
          actor.send(sender, ExecuteActionResp("Action not found"))
          actor.continue(ps)
        }
        StatusCheck(sender:) -> {
          actor.send(sender, StatusCheckResp)
          actor.continue(ps)
        }
        Register(sender:, server_addr:) -> {
          actor.send(sender, RegisterResp(Description))
          actor.continue(PresenceSensor(..ps, server_addr: Some(server_addr)))
        }
      }
  }
}

pub fn send_state(ps: PresenceSensor, host: String, port: Int) -> Nil {
  process.spawn_unlinked(fn() {
    let assert Ok(req) =
      request.to(
        "http://"
        <> host
        <> ":"
        <> int.to_string(port)
        <> "/api/devices/"
        <> ps.id
        <> "/property/presence-detected",
      )

    let value =
      case ps.state {
        PresenceDetected -> True
        PresenceNotDetected -> False
      }
      |> bool.to_string
      |> string.lowercase

    let response =
      req
      |> request.prepend_header("Content-Type", "application/json")
      |> request.set_body("{value: " <> value <> "}")
      |> httpc.send()

    case response {
      Error(InvalidUtf8Response) -> io.println_error("Invalid UTF8 reponse")
      Error(FailedToConnect(_, _)) -> io.println_error("Failed to connect")
      Ok(res) if res.status >= 200 && res.status < 300 -> Nil
      Ok(res) ->
        { "Error in response " <> int.to_string(res.status) <> " " <> res.body }
        |> io.println_error
    }
  })
  Nil
}
