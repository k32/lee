%% @private
-module(lee_sup).

-behaviour(supervisor).

%% API
-export([start_link/0]).

%% Supervisor callbacks
-export([init/1]).

-define(SERVER, ?MODULE).

%%%===================================================================
%%% API functions
%%%===================================================================

start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

%%%===================================================================
%%% Supervisor callbacks
%%%===================================================================

init([]) ->
    SupFlags = #{},
    InitialData = [], %% TODO
    LeeServer = #{ id => lee_server
                 , start => {lee_server, start_link, [InitialData]}
                 },
    {ok, {SupFlags, [LeeServer]}}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
