-module(lee_tests).

-include_lib("eunit/include/eunit.hrl").
-include_lib("lee/include/lee.hrl").
-include_lib("lee/src/framework/lee_internal.hrl").
-include_lib("lee/include/lee_types.hrl").

-define(moc, {[], #{}, #{}}).

namespace_test() ->
    ?assertMatch( #{foo := #{bar := #{baz := #{}}}}
                , lee:namespace([foo, bar], #{baz => #{}})
                ).

run_validate(Model, Config0) ->
    Config = [{set, K, V} || {K, V} <- maps:to_list(Config0)],
    Data = lee_storage:patch( lee_storage:new(lee_map_storage, [])
                            , Config
                            ),
    catch lee:validate(Model, Data).

-define(valid(Config),
        ?assertMatch( {ok, _}
                    , run_validate(Model, Config)
                    )).

-define(invalid(Config),
        ?assertMatch( {error, _, _}
                    , run_validate(Model, Config)
                    )).

validate_test() ->
    Model0 = #{ foo => {[value]
                       , #{type => lee_types:boolean()}
                       }
              , bar => {[value]
                       , #{type => lee_types:integer(), default => 42}
                       }
              },
    Model1 = Model0 #{ baz => {[map]
                              , #{}
                              , Model0
                              }
                     },
    {ok, Model} = lee_model:compile( [lee:base_metamodel()]
                                   , [lee:base_model(), Model1]
                                   ),
    ?valid(#{[foo] => true}),
    ?valid(#{[foo] => true, [bar] => 1}),
    ?valid(#{[foo] => false, [bar] => -12}),
    ?invalid(#{}),
    ?invalid(#{[bar] => 1}),
    ?invalid(#{[foo] => 1}),
    ?invalid(#{[foo] => true, [bar] => 1.0}),
    ?valid(#{ [baz, ?lcl(1), foo] => true
            , [baz, ?lcl(1), bar] => 1
            , [foo] => true
            }),
    ?valid(#{ [baz, ?lcl(1), foo] => false
            , [foo] => true
            }),
    ?invalid(#{ [baz, ?lcl(1), foo] => foo
              , [foo] => true
              }),
    ?invalid(#{ [baz, ?lcl(1), bar] => 1
              , [foo] => true
              }),
    ok.

get_test() ->
    Model0 = #{ foo => {[value]
                       , #{type => lee_types:boolean()}
                       }
              , bar => {[value]
                       , #{type => lee_types:integer(), default => 42}
                       }
              },
    Model1 = Model0 #{ baz => {[map], #{}, Model0}},
    Model2 = Model1 #{ baz => {[map], #{}, Model1}},
    {ok, Model} = lee_model:compile( [lee:base_metamodel()]
                                   , [lee:base_model(), Model2]
                                   ),
    Patch = [ {set, [foo],                              true }
            , {set, [baz, ?lcl(0), foo],                true }
            , {set, [baz, ?lcl(0), bar],                0    }
            , {set, [baz, ?lcl(1), foo],                false}
            , {set, [baz, ?lcl(0), baz, ?lcl(42), foo], false}
            ],
    Config = lee_storage:patch( lee_storage:new(lee_map_storage)
                              , Patch
                              ),
    ?assertMatch(true, lee:get(Model, Config, [foo])),
    ?assertMatch(42, lee:get(Model, Config, [bar])),

    ?assertMatch(0, lee:get(Model, Config, [baz, ?lcl(0), bar])),
    ?assertMatch(true, lee:get(Model, Config, [baz, ?lcl(0), foo])),

    ?assertMatch(false, lee:get(Model, Config, [baz, ?lcl(1), foo])),
    ?assertMatch(42, lee:get(Model, Config, [baz, ?lcl(1), bar])),

    ?assertMatch(false, lee:get(Model, Config, [baz, ?lcl(0), baz, ?lcl(42), foo])),
    ?assertMatch(42, lee:get(Model, Config, [baz, ?lcl(0), baz, ?lcl(42), bar])),
    ok.

from_string_test() ->
    {ok, M} = lee_model:compile([], [lee:base_model()]),
    ?assertMatch({ok, true},  lee:from_string(M, lee_types:boolean(), "true")),
    ?assertMatch({ok, false}, lee:from_string(M, lee_types:boolean(), "false")),
    ?assertMatch({ok, 1}, lee:from_string(M, lee_types:boolean(), "1")),
    ?assertMatch({ok, 1.1}, lee:from_string(M, lee_types:boolean(), "1.1")),
    ?assertMatch({ok, {foo, "bar", []}}, lee:from_string(M, lee_types:boolean(), "{foo, \"bar\", []}")),
    ?assertMatch({error, _}, lee:from_string(M, lee_types:boolean(), "")),
    ?assertMatch({error, _}, lee:from_string(M, lee_types:boolean(), ",")),
    ok.
