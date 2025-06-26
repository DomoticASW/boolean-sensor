import boolean_sensor_actor.{
  type BooleanSensorMessage, type DeviceDescription,
  type DevicePropertyDescription, type TypeConstraintsDescription, type Types,
  BoolType, RegisterResp, ServerAddress, StatusCheckResp,
} as bs_actor
import gleam/dynamic/decode
import gleam/erlang/process.{type Subject}
import gleam/http.{Get, Post}
import gleam/json.{type Json}
import gleam/otp/actor
import middleware
import wisp.{type Request, type Response}

pub fn handle_request(
  req: Request,
  bs: Subject(BooleanSensorMessage),
) -> Response {
  use req <- middleware.basic(req)
  case wisp.path_segments(req) {
    ["register"] -> register(req, bs)
    ["check-status"] -> check_status(req, bs)
    _ -> wisp.not_found()
  }
}

fn register(req: Request, bs: Subject(BooleanSensorMessage)) -> Response {
  use <- wisp.require_method(req, Post)
  use body <- wisp.require_json(req)

  case decode.run(body, register_body_decoder()) {
    Error(_) -> {
      json.string("Body format was wrong")
      |> json.to_string_tree()
      |> wisp.json_response(400)
    }
    Ok(RegisterBody(server_port:)) -> {
      let host = req.host
      let assert RegisterResp(device_description:) =
        actor.call(bs, 5000, bs_actor.register_msg(
          _,
          ServerAddress(host, server_port),
        ))
      encode_device_description(device_description)
      |> json.to_string_tree()
      |> wisp.json_response(200)
    }
  }
}

fn check_status(req: Request, bs: Subject(BooleanSensorMessage)) -> Response {
  use <- wisp.require_method(req, Get)
  let assert StatusCheckResp = actor.call(bs, 5000, bs_actor.status_check_msg)
  wisp.response(200)
}

// ****** DECODING FROM JSON FUNCTIONS ******

type RegisterBody {
  RegisterBody(server_port: Int)
}

fn register_body_decoder() -> decode.Decoder(RegisterBody) {
  use server_port <- decode.field("serverPort", decode.int)
  decode.success(RegisterBody(server_port:))
}

// ****** ENCODING TO JSON FUNCTIONS ******

fn encode_device_description(d: DeviceDescription) -> Json {
  json.object([
    #("id", json.string(d.id)),
    #("name", json.string(d.name)),
    #(
      "properties",
      json.array(d.properties, encode_device_property_description),
    ),
    #("actions", json.preprocessed_array([])),
    #("events", json.array(d.events, json.string)),
  ])
}

fn encode_device_property_description(d: DevicePropertyDescription) -> Json {
  json.object([
    #("id", json.string(d.id)),
    #("name", json.string(d.name)),
    #("value", json.bool(d.value)),
    #(
      "typeConstraints",
      encode_type_constraints_description(d.type_constraints),
    ),
  ])
}

fn encode_type_constraints_description(tc: TypeConstraintsDescription) -> Json {
  case tc {
    bs_actor.None(type_:) ->
      json.object([
        #("constraint", json.string("None")),
        #("type", encode_types(type_)),
      ])
  }
}

fn encode_types(type_: Types) -> Json {
  case type_ {
    BoolType -> json.string("Boolean")
  }
}
