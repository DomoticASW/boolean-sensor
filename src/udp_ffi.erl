-module(udp_ffi).

-export([send/4, close/1]).

send(Socket, Host, Port, Packet) ->
  case gen_udp:send(Socket, Host, Port, Packet) of
    ok ->
      {ok, nil};
    {error, Reason} ->
      {error, Reason}
  end.

close(Socket) ->
    gen_udp:close(Socket),
    ok.
