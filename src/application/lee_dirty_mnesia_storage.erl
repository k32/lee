%% @doc Simple storage backend based on dirty Mnesia reads
%%
%% This storage backend is read-only, patching is not supported (and
%% creation too, for that matter). Therefore this backend can only be
%% used as a dirty view of a transactional Mnesia storage
-module(lee_dirty_mnesia_storage).

-behavior(lee_storage).

-include("lee.hrl").

-export([ create/1
        , get/2
        , patch/3
        ]).

-export([from_table/1]).

%%====================================================================
%% API functions
%%====================================================================

%% @doc Create a dirty read-only view of a Mnesia table `TabName'
-spec from_table(atom()) -> lee_storage:data(_).
from_table(TabName) ->
    lee_storage:wrap(?MODULE, TabName).

%%====================================================================
%% lee_storage callbacks
%%====================================================================

%% @private Unsupported
create(_Options) ->
    error(unsupported).

%% @private
get(Key, TabName) ->
    case mnesia:dirty_read(TabName, Key) of
        [{_, Key, Val}] ->
            {ok, Val};
        [] ->
            undefined
    end.

%% @private Unsupported
patch(_TabName, _Delete, _Set) ->
    %% Dirty patches are not allowed.
    error(unsupported).
