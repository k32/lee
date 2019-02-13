-module(lee_storage).

-include("lee_internal.hrl").

-export([ new/2
        , get/2
        , put/2
        , list/2
        ]).

-export_type([ storage/0
             ]).

-type storage() :: term().

-callback create(Options :: term()) ->
    storage().

-callback get(lee:key(), storage()) ->
    {ok, term()} | undefined.

-callback put(A, [{lee:key(), term()}]) -> A
    when A :: storage().

-spec new(module(), term()) -> lee:data().
new(Module, Options) ->
    #data{ backend = Module
         , data    = Module:create(Options)
         }.

-spec get(lee:key(), #data{}) -> {ok, term()}
                               | undefined.
get(Key, #data{backend = Backend, data = Data}) ->
    Backend:get(Key, Data).

-spec put(lee:data(), [{lee:key(), term()}] | #{lee:key() => term()}) ->
                 lee:data().
put(Data, Patch) when is_map(Patch) ->
    %% TODO: Optimize this
    ?MODULE:put(Data, maps:to_list(Patch));
put(A = #data{backend = Backend, data = Data}, Patch) ->
    A#data{ data = Backend:put(Data, Patch) }.

%% List instances that can match the pattern
-spec list(lee:key(), lee:data()) -> [lee:key()].
list(Pattern, #data{backend = Module, data = Data}) ->
    list(Module, Data, [], Pattern).

list(Module, Data, Prefix, []) ->
    [Prefix];
list(Module, Data, Prefix0, Pattern) ->
    Pred = fun(?children) -> false;
              (_)         -> true
           end,
    case lists:splitwith(Pred, Pattern) of
        {Prefix1, [?children | Rest]} ->
            Prefix = Prefix0 ++ Prefix1,
            case Module:get(Prefix ++ [?children], Data) of
                {ok, L}   -> ok;
                undefined -> L = []
            end,
            lists:append([ list(Module, Data, Prefix ++ [?lcl(I)], Rest)
                         || I <- L
                         ]);
        {Pattern, []} ->
            [Prefix0 ++ Pattern]
    end.
