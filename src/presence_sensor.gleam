import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/option.{None, Some}
import gleam/otp/actor
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
    timer_actor.TimePassed(sender: timer, ms: _) -> {
      case timer == ps.loop_timer {
        False ->
          case int.random(5) {
            0 -> PresenceSensor(..ps, state: PresenceDetected)
            _ -> PresenceSensor(..ps, state: PresenceNotDetected)
          }
        True -> {
          case ps.server_addr {
            None -> ps
            Some(_) -> todo as "send updates to server"
          }
        }
      }
      |> actor.continue
    }
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
