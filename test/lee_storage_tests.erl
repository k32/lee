-module(lee_storage_tests).

-include_lib("eunit/include/eunit.hrl").
-include_lib("lee/include/lee.hrl").

patch() ->
    [ {[foo, bar], 1}
    , {[bar, baz], 2}
    , {[baz, ?lcl(1), foo], 1}
    , {[baz, ?lcl(1), bar], 1}
    , {[baz, ?lcl(2), foo], 1}
    , {[baz, ?lcl(2), bar], 1}
    , {[quux, ?lcl(1), foo, ?lcl(1)], 11}
    , {[quux, ?lcl(1), foo, ?lcl(2)], 1}
    ].

get_test() ->
    Data0 = lee_storage:new(lee_map_storage, []),
    Data = lee_storage:put(Data0, patch()),
    ?assertMatch({ok, 1}, lee_storage:get([foo, bar], Data)),
    ?assertMatch({ok, 2}, lee_storage:get([bar, baz], Data)),
    ?assertMatch({ok, 11}, lee_storage:get([quux, ?lcl(1), foo, ?lcl(1)], Data)),
    ?assertMatch(undefined, lee_storage:get([quux, ?lcl(1), foo, ?lcl(3)], Data)).

get_children_test() ->
    Data0 = lee_storage:new(lee_map_storage, []),
    Data = lee_storage:put(Data0, patch()),
    ?assertMatch({ok, [1, 2]}, lee_storage:get([baz, ?children], Data)),
    ?assertMatch({ok, [1]}, lee_storage:get([quux, ?children], Data)),
    ?assertMatch({ok, [1, 2]}, lee_storage:get([quux, ?lcl(1), foo, ?children], Data)).

list_test() ->
    Data0 = lee_storage:new(lee_map_storage, []),
    Data = lee_storage:put(Data0, patch()),
    %% Patterns that don't contain ?children should be just returned
    %% back:
    ?assertMatch([[foo, bar]], lee_storage:list([foo, bar], Data)),
    ?assertMatch([[baz]], lee_storage:list([baz], Data)),
    ?assertMatch( [[quux, ?lcl(1), foo]]
                , lee_storage:list([quux, ?lcl(1), foo], Data)
                ),
    %% Single ?children in a pattern:
    ?assertMatch( [ [baz, ?lcl(1)]
                  , [baz, ?lcl(2)]
                  ]
                , lee_storage:list([baz, ?children], Data)
                ),
    ?assertMatch( [[quux, ?lcl(1)]]
                , lee_storage:list([quux, ?children], Data)
                ),
    %% Add normal key after ?children:
    ?assertMatch( [ [baz, ?lcl(1), foo]
                  , [baz, ?lcl(2), foo]
                  ]
                , lee_storage:list([baz, ?children, foo], Data)
                ),
    %% Child instance in the pattern:
    ?assertMatch( [ [quux, ?lcl(1), foo, ?lcl(1)]
                  , [quux, ?lcl(1), foo, ?lcl(2)]
                  ]
                , lee_storage:list([quux, ?lcl(1), foo, ?children], Data)
                ),
    %% Multiple ?children in the pattern:
    ?assertMatch( [ [quux, ?lcl(1), foo, ?lcl(1)]
                  , [quux, ?lcl(1), foo, ?lcl(2)]
                  ]
                , lee_storage:list([quux, ?children, foo, ?children], Data)
                ),
    %% Missing key:
    ?assertMatch( []
                , lee_storage:list([quux, ?lcl(2), foo, ?children], Data)
                ).
