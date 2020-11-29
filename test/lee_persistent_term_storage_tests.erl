-module(lee_persistent_term_storage_tests).

-include_lib("eunit/include/eunit.hrl").
-include_lib("lee/include/lee.hrl").

patch() ->
    [ {set, [foo, bar], 1}
    , {set, [bar, baz], 2}
    ].

get_test() ->
    Storage = lee_storage:new(lee_persistent_term_storage, test),
    lee_storage:patch(Storage, patch()),
    ?assertMatch({ok, 1}, lee_storage:get([foo, bar], Storage)),
    ?assertMatch({ok, 2}, lee_storage:get([bar, baz], Storage)),
    ?assertMatch(undefined, lee_storage:get([baz, foo], Storage)),
    lee_storage:patch(Storage, [{rm, [foo, bar]}]),
    ?assertMatch(undefined, lee_storage:get([foo, bar], Storage)).
