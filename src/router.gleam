import gleam/erlang/process.{type Subject}
import gleam/http.{Post}
import gleam/json.{type Json}
import gleam/otp/actor
import middleware
import presence_sensor.{
  type DeviceDescription, type DevicePropertyDescription,
  type PresenceSensorMessage, type TypeConstraintsDescription, type Types,
  BoolType, RegisterResp, ServerAddress,
}
import wisp.{type Request, type Response}

pub fn handle_request(
  req: Request,
  ps: Subject(PresenceSensorMessage),
) -> Response {
  use req <- middleware.basic(req)
  case wisp.path_segments(req) {
    ["register"] -> register(req, ps)
    _ -> wisp.not_found()
  }
}

fn register(req: Request, ps: Subject(PresenceSensorMessage)) -> Response {
  use <- wisp.require_method(req, Post)
  let assert RegisterResp(device_description:) =
    actor.call(ps, 5000, presence_sensor.register_msg(
      _,
      ServerAddress("localhost", 3000),
    ))
  encode_device_description(device_description)
  |> json.to_string_tree()
  |> wisp.json_response(200)
}

// ****** ENCODING TO JSON FUNCTIONS ******

pub fn encode_device_description(d: DeviceDescription) -> Json {
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

pub fn encode_device_property_description(d: DevicePropertyDescription) -> Json {
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

pub fn encode_type_constraints_description(
  tc: TypeConstraintsDescription,
) -> Json {
  case tc {
    presence_sensor.None(type_:) ->
      json.object([
        #("constraint", json.string("None")),
        #("type", encode_types(type_)),
      ])
  }
}

pub fn encode_types(type_: Types) -> Json {
  case type_ {
    BoolType -> json.string("Boolean")
  }
}
