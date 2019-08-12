-module(lee_consult_tests).

-include_lib("eunit/include/eunit.hrl").
-include_lib("typerefl/include/types.hrl").
-include_lib("lee/include/lee.hrl").

model() ->
    Model0 = #{ list => {[value, consult, foo]
                        , #{ file_key => list
                           , type => string()
                           }
                        }
              , deps => {[value, consult, bar]
                        , #{ file_key => deps
                           , type => string()
                           }
                        }
              },
    FooBar = #{ metatype =>
                    #{ foo => {[metatype], #{}}
                     , bar => {[metatype], #{}}
                     }},
    Meta = [lee:base_metamodel(), lee_consult:metamodel(), FooBar],
    {ok, Model} = lee_model:compile(Meta, [Model0]),
    Model.

proplist_test() ->
    Model = model(),
    Data = lee_consult:read_to( Model
                              , "test/data/demo-correct-1.eterm"
                              , lee_storage:new(lee_map_storage, [])
                              ),
    %% io:format(user, "~p~n", [Data]),
    ?assertMatch( [foo, bar, baz]
                , lee:get(Model, Data, [list])
                ),
    ?assertMatch( [ {map_sets, {git, "https://github.com/k32/map_sets"}, {tag, "0.1.1"}}
                  , {getopt,   "1.0.1"}
                  ]
                , lee:get(Model, Data, [deps])
                ).

map_test() ->
    Model = model(),
    Data = lee_consult:read_to( Model
                              , "test/data/demo-correct-1-map.eterm"
                              , lee_storage:new(lee_map_storage, [])
                              ),
    ?assertMatch( [foo, bar, baz]
                , lee:get(Model, Data, [list])
                ),
    ?assertMatch( [ {map_sets, {git, "https://github.com/k32/map_sets"}, {tag, "0.1.1"}}
                  , {getopt,   "1.0.1"}
                  ]
                , lee:get(Model, Data, [deps])
                ).

missing_file_test() ->
    Model = model(),
    ?assertMatch( {error, _}
                , catch lee_consult:read_to( Model
                                           , "test/data/this-file-does-not-exist.eterm"
                                           , lee_storage:new(lee_map_storage, [])
                                           )
                ).

improper_format_test() ->
    Model = model(),
    ?assertMatch( {error, _}
                , catch lee_consult:read_to( Model
                                           , "test/data/garbage.txt"
                                           , lee_storage:new(lee_map_storage, [])
                                           )
                ).

not_proplist_test() ->
    Model = model(),
    ?assertMatch( {error, _}
                , catch lee_consult:read_to( Model
                                           , "test/data/not-proplist.eterm"
                                           , lee_storage:new(lee_map_storage, [])
                                           )
                ).

filter_by_metatype_test() ->
    Model = model(),
    ?assertMatch( [{set, [list], [foo,bar,baz]}]
                , lee_consult:read(Model, "test/data/demo-correct-1.eterm", [foo])
                ).
