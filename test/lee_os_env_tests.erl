-module(lee_os_env_tests).

-include_lib("eunit/include/eunit.hrl").
-include_lib("typerefl/include/types.hrl").

model() ->
    Model0 = #{ home => {[value, os_env],
                         #{ os_env => "HOME"
                          , type => string()
                          }}
              , path => {[value, os_env],
                         #{ os_env => "PATH"
                          , type => string()
                          }}
              },
    Meta = [lee:base_metamodel(), lee_os_env:metamodel()],
    {ok, Model} = lee_model:compile(Meta, [Model0]),
    Model.

osenv_test() ->
    Model = model(),
    Data = lee_os_env:read_to( Model
                             , lee_storage:new(lee_map_storage, [])
                             ),
    Home = os:getenv("HOME"),
    Path = os:getenv("PATH"),
    ?assertMatch( Home
                , lee:get(Model, Data, [home])
                ),
    ?assertMatch( Path
                , lee:get(Model, Data, [path])
                ).
