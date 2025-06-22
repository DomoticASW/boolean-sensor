import boolean_sensor_actor.{
  type BooleanSensorMessage, type DeviceDescription,
  type DevicePropertyDescription, type TypeConstraintsDescription, type Types,
  BoolType, RegisterResp, ServerAddress, StatusCheckResp,
} as ps_actor
import gleam/erlang/process.{type Subject}
import gleam/http.{Get, Post}
import gleam/json.{type Json}
import gleam/otp/actor
import middleware
import wisp.{type Request, type Response}

pub fn handle_request(
  req: Request,
  ps: Subject(BooleanSensorMessage),
) -> Response {
  use req <- middleware.basic(req)
  case wisp.path_segments(req) {
    ["register"] -> register(req, ps)
    ["check-status"] -> check_status(req, ps)
    _ -> wisp.not_found()
  }
}

fn register(req: Request, ps: Subject(BooleanSensorMessage)) -> Response {
  use <- wisp.require_method(req, Post)
  let assert RegisterResp(device_description:) =
    actor.call(ps, 5000, ps_actor.register_msg(
      _,
      ServerAddress("localhost", 3000),
    ))
  encode_device_description(device_description)
  |> json.to_string_tree()
  |> wisp.json_response(200)
}

fn check_status(req: Request, ps: Subject(BooleanSensorMessage)) -> Response {
  use <- wisp.require_method(req, Get)
  let assert StatusCheckResp = actor.call(ps, 5000, ps_actor.status_check_msg)
  wisp.response(200)
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
    ps_actor.None(type_:) ->
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
