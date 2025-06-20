import gleam/erlang/process
import mist
import presence_sensor
import router
import wisp
import wisp/wisp_mist

pub fn main() -> Nil {
  let assert Ok(actor) = presence_sensor.actor()
  wisp.configure_logger()
  let secret_key_base = wisp.random_string(64)

  let assert Ok(_) =
    wisp_mist.handler(router.handle_request(_, actor.data), secret_key_base)
    |> mist.new
    |> mist.port(8088)
    |> mist.start()
  process.sleep_forever()
}
