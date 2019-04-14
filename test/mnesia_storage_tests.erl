-module(mnesia_storage_tests).

-include_lib("eunit/include/eunit.hrl").
-include_lib("lee/include/lee.hrl").

patch() ->
    [ {set, [foo, bar], 1}
    , {set, [bar, baz], 2}
    , {set, [baz, ?lcl(1), foo], 1}
    , {set, [baz, ?lcl(1), bar], 1}
    , {set, [baz, ?lcl(2), foo], 1}
    , {set, [baz, ?lcl(2), bar], 1}
    , {set, [quux, ?lcl(1), foo, ?lcl(1)], 11}
    , {set, [quux, ?lcl(1), foo, ?lcl(2)], 1}
    ].

patch2() ->
    [ {rm, [foo, bar]}
    , {rm, [baz, ?lcl(1)]}
    , {rm, [quux, ?lcl(1), foo, ?lcl(1)]}
    , {rm, [quux, ?lcl(1), foo, ?lcl(2)]}
    ].

-define(assertMatchT(A, B),
        ?assertMatch( {atomic, A}
                    , mnesia:transaction(fun() -> B end)
                    )).

get_test() ->
    application:ensure_all_started(mnesia),
    Data = lee_mnesia_storage:ensure_table(?FUNCTION_NAME, []),
    ok = lee_mnesia_storage:patch(Data, patch()),
    ?assertMatchT({ok, 1}, lee_storage:get([foo, bar], Data)),
    ?assertMatchT({ok, 2}, lee_storage:get([bar, baz], Data)),
    ?assertMatchT({ok, 11}, lee_storage:get([quux, ?lcl(1), foo, ?lcl(1)], Data)),
    ?assertMatchT(undefined, lee_storage:get([quux, ?lcl(1), foo, ?lcl(3)], Data)).

get_after_delete_test() ->
    application:ensure_all_started(mnesia),
    Data = lee_mnesia_storage:ensure_table(?FUNCTION_NAME, []),
    ok = lee_mnesia_storage:patch(Data, patch()),
    ok = lee_mnesia_storage:patch(Data, patch2()),
    %% Check that simple key gets deleted:
    ?assertMatchT(undefined, lee_storage:get([foo, bar], Data)),
    ?assertMatchT(undefined, lee_storage:get([quux, ?lcl(1), foo, ?lcl(1)], Data)),
    ?assertMatchT(undefined, lee_storage:get([quux, ?lcl(1), foo, ?lcl(3)], Data)),
    %% Check recursive deleteions:
    ?assertMatchT(undefined, lee_storage:get([baz, ?lcl(1), foo], Data)),
    ?assertMatchT(undefined, lee_storage:get([baz, ?lcl(1), bar], Data)),
    %% But the rest of data is left (more or less) intact
    ?assertMatchT({ok, 2}, lee_storage:get([bar, baz], Data)),
    ?assertMatchT({ok, 1}, lee_storage:get([baz, ?lcl(2), foo], Data)),
    ?assertMatchT({ok, 1}, lee_storage:get([baz, ?lcl(2), bar], Data)).

get_dirty_test() ->
    application:ensure_all_started(mnesia),
    Data0 = lee_mnesia_storage:ensure_table(?FUNCTION_NAME, []),
    ok = lee_mnesia_storage:patch(Data0, patch()),
    Data = lee_dirty_mnesia_storage:from_table(?FUNCTION_NAME),
    ?assertMatch({ok, 1}, lee_storage:get([foo, bar], Data)),
    ?assertMatch({ok, 2}, lee_storage:get([bar, baz], Data)),
    ?assertMatch({ok, 11}, lee_storage:get([quux, ?lcl(1), foo, ?lcl(1)], Data)),
    ?assertMatch(undefined, lee_storage:get([quux, ?lcl(1), foo, ?lcl(3)], Data)).
