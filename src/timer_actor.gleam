import gleam/erlang/process.{type Subject}
import gleam/otp/actor

pub type Timer(m) {
  StartedTimer(
    target: process.Subject(TimePassed(m)),
    self: Subject(Message),
    ms: Int,
  )
  StoppedTimer(target: process.Subject(TimePassed(m)), self: Subject(Message))
}

pub opaque type Message {
  Start(ms: Int)
  Stop
  Loop
}

pub const start = Start

pub const stop = Stop

pub type TimePassed(m) {
  TimePassed(sender: Subject(Message), ms: Int)
  Other(m)
}

pub fn timer_actor(
  target: process.Subject(TimePassed(m)),
) -> Result(actor.Started(process.Subject(Message)), actor.StartError) {
  actor.new_with_initialiser(50, fn(self) {
    StoppedTimer(target:, self:)
    |> actor.initialised()
    |> actor.returning(self)
    |> Ok
  })
  |> actor.on_message(handle_message)
  |> actor.start
}

fn handle_message(t: Timer(m), msg: Message) -> actor.Next(Timer(m), Message) {
  case t {
    StartedTimer(target:, self:, ms:) ->
      case msg {
        Loop -> {
          actor.send(target, TimePassed(self, ms))
          process.sleep(ms)
          actor.send(self, Loop)
          actor.continue(t)
        }
        Start(ms:) -> actor.continue(StartedTimer(..t, ms:))
        Stop -> actor.continue(StoppedTimer(target:, self:))
      }
    StoppedTimer(target:, self:) ->
      case msg {
        Start(ms:) -> {
          process.sleep(ms)
          actor.send(self, Loop)
          actor.continue(StartedTimer(target:, self:, ms:))
        }
        Stop | Loop -> actor.continue(t)
      }
  }
}
