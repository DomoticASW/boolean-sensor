import gleam/bytes_tree.{type BytesTree}

pub type Address =
  #(Int, Int, Int, Int)

pub type Socket

pub type SocketOption {
  Binary
  Active(ActiveType)
  Sndbuf(Int)
  Recbuf(Int)
}

pub type ActiveType {
  Once
}

@external(erlang, "gen_udp", "open")
pub fn open(port: Int, opts: List(SocketOption)) -> Result(Socket, Nil)

@external(erlang, "udp_ffi", "close")
pub fn close(socket: Socket) -> Nil 

@external(erlang, "udp_ffi", "send")
pub fn send(
  socket: Socket,
  host: Address,
  port: Int,
  packet: BytesTree,
) -> Result(Nil, Nil)
