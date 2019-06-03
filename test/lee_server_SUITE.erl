-module(lee_server_SUITE).

-compile(export_all).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").
-include_lib("typerefl/include/types.hrl").

-define(assertMatchT(A, B),
        ?assertMatch( {atomic, A}
                    , mnesia:transaction(fun() -> B end)
                    )).

model() ->
    #{ path =>
           {[value, os_env],
            #{ type => string()
             , os_env => "PATH"
             }}
     , foo =>
           {[value],
            #{ type => integer()
             }}
     , bar =>
           {[value],
            #{ type => term()
             , default => default
             }}
     }.

metamodel() ->
    lee_os_env:metamodel().

initial_data() ->
    [ {set, [path], "initial"}
    , {set, [foo], 0}
    ].

all() ->
    [t_patch, t_trans_read].

t_patch(_Config) ->
    %% Validate initial data
    ?assertMatch("initial", lee_server:get_d([path])),
    ?assertMatch(0, lee_server:get_d([foo])),
    %% Validate the defaults:
    ?assertMatch(default, lee_server:get_d([bar])),
    %% Check arguments of patch function:
    ?assertMatch( ok
                , lee_server:patch(
                    fun(Model, Data) ->
                            0 = lee:get(Model, Data, [foo]),
                            default = lee:get(Model, Data, [bar]),
                            {ok, []}
                    end)
                ),
    %% Try invalid patch:
    ?assertMatch( {error, {invalid_config
                          , ["[foo]: Mandatory value is missing in the config"]
                          , []
                          }}
                , lee_server:patch(
                    fun(_, _) ->
                            {ok, [ {set, [path], "invalid"}
                                 , {rm, [foo]}
                                 ]}
                    end)
                ),
    %% Verify that it didn't leave side effects:
    ?assertMatch("initial", lee_server:get_d([path])),
    %% Apply a valid patch:
    ?assertMatch( ok
                , lee_server:patch(
                    fun(Model, _) ->
                            P1 = lee_os_env:read(Model),
                            P2 = [{set, [foo], 3}],
                            {ok, P1 ++ P2}
                    end)
                ),
    %% Verify changes:
    ?assertEqual(os:getenv("PATH"), lee_server:get_d([path])),
    ?assertMatch(3, lee_server:get_d([foo])),
    ?assertMatch(default, lee_server:get_d([bar])).

t_trans_read(_Config) ->
    ?assertMatchT( {0, "initial", [[foo]]}
                 , { lee_server:get([foo])
                   , lee_server:get([path])
                   , lee_server:list([foo])
                   }
                 ).

suite() ->
    [{timetrap, {seconds, 30}}].

init_per_suite(Config) ->
    application:ensure_all_started(mnesia),
    Config.

end_per_suite(_Config) ->
    ok.

init_per_testcase(_TestCase, Config) ->
    %% Start server:
    application:set_env(lee, interface_modules, [?MODULE]),
    {ok, Pid} = lee_server:start_link(initial_data()),
    [{lee_server_pid, Pid} | Config].

end_per_testcase(_TestCase, Config) ->
    gen_server:stop(?config(lee_server_pid, Config)),
    ok.
