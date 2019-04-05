-module(lee_os_env_tests).

-include_lib("eunit/include/eunit.hrl").
-include_lib("lee/include/lee.hrl").

model() ->
    Model0 = #{ home => {[value, environment_variable]
                        , #{os_env => "HOME"}
                        }
              , path => {[value, environment_variable]
                        , #{os_env => "PATH"}
                        }
              },
    {ok, Model} = lee_model:compile([], [Model0]),
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
