import gleam/erlang/process
import presence_sensor

pub fn main() -> Nil {
  let assert Ok(_) = presence_sensor.actor()
  process.sleep_forever()
}
