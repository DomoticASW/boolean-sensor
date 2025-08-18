import gleam/bytes_tree.{type BytesTree}
import gleam/erlang/atom.{type Atom}

pub type Address =
  #(Int, Int, Int, Int)

pub type Socket

pub type SocketOption {
  Binary
  Active(ActiveType)
  Sndbuf(Int)
  Recbuf(Int)
  Broadcast(Bool)
}

pub type ActiveType {
  Once
}

@external(erlang, "gen_udp", "open")
pub fn open(port: Int, opts: List(SocketOption)) -> Result(Socket, Nil)

@external(erlang, "udp_ffi", "close")
pub fn close(socket: Socket) -> Nil

pub fn send(
  socket: Socket,
  host: Address,
  port: Int,
  packet: BytesTree,
) -> Result(Nil, String) {
  case send_internal(socket, host, port, packet) {
    Ok(_) -> Ok(Nil)
    Error(reason) -> Error(atom.to_string(reason))
  }
}

@external(erlang, "udp_ffi", "send")
fn send_internal(
  socket: Socket,
  host: Address,
  port: Int,
  packet: BytesTree,
) -> Result(Nil, Atom)
