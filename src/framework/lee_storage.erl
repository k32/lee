-module(lee_storage).

-include("lee_internal.hrl").

-export([ new/2
        , new/1
        , get/2
        , patch/2
        , list/2
        , fold/3
        , fold/4
        ]).

-export_type([ data/1
             , patch/1
             ]).

%%====================================================================
%% Types
%%====================================================================

-define(rose_tree, '$rose_tree').

-type storage(_A) :: term().

-type patch(A) :: [{set, lee:key(), A} | {rm, lee:key()}].

-type rose_tree() :: #{lee:key() => rose_tree()}.

-record(lee_tree,
        { %% Callback module implementing key-value storage:
          backend
          %% Key-value storage for values (grants us fast `get'):
        , data
        }).

-opaque data(A) :: #lee_tree{ backend :: module()
                            , data    :: storage(A | rose_tree())
                            }.

%%====================================================================
%% Callbacks
%%====================================================================

-callback create(Options :: term()) -> storage(_).

-callback get(term(), storage(Val)) -> {ok, Val}
                                     | undefined.

-callback patch(Storage, Delete, Set) -> Storage
    when Storage :: storage(Val)
       , Delete  :: [lee:key()]
       , Set     :: [{lee:key(), Val}].

%%====================================================================
%% API function
%%====================================================================

-spec new(module(), map()) -> data(_).
new(Backend, Options) ->
    Data0 = Backend:create(Options),
    Data  = Backend:patch(Data0, [], [{?rose_tree, #{}}]),
    #lee_tree{ backend = Backend
             , data    = Data
             }.

-spec new(module()) -> data(_).
new(Module) ->
    new(Module, #{}).

-spec get(lee:key(), data(A)) -> {ok, A} | undefined.
get(Key, #lee_tree{backend = Backend, data = Data}) ->
    Backend:get(Key, Data).

-spec patch(data(A), patch(A)) -> data(A).
patch(D0 = #lee_tree{backend = Backend, data = Data0}, Patch0) ->
    {ok, Keys0} = Backend:get(?rose_tree, Data0),
    {Delete, Set} = transform_patch(D0, Patch0),
    Keys1 = lists:foldl(fun rt_del/2, Keys0, Delete),
    Keys = lists:foldl(fun rt_add/2, Keys1, [K || {K, _} <- Set]),
    Data = Backend:patch(Data0, Delete, [{?rose_tree, Keys} | Set]),
    D0#lee_tree{ data = Data
               }.

%% List instances that can match the pattern
-spec list(lee:key(), data(_)) -> [lee:key()].
list(Pattern, #lee_tree{backend = Backend, data = Data}) ->
    {ok, Keys} = Backend:get(?rose_tree, Data),
    list(Keys, [], Pattern).


-spec fold( fun((lee:key(), Val, Acc) -> Acc)
          , Acc
          , data(Val)
          ) -> Acc.
fold(Fun0, Acc0, Data) ->
    Fun = fun(Key, Val, Acc, _) ->
                  {Fun0(Key, Val, Acc), ?unused}
          end,
    fold(Fun, Acc0, ?unused, Data).

-spec fold( fun((lee:key(), Val, Acc, Scope) -> {Acc, Scope})
          , Acc
          , Scope
          , data(Val)
          ) -> Acc.
fold(Fun0, Acc0, Scope0, Data) ->
    #lee_tree{ data    = Storage
             , backend = Backend
             } = Data,
    {ok, Keys} = Backend:get(?rose_tree, Storage),
    Fun = fun(Key, Acc, Scope) ->
                  case Backend:get(Key, Storage) of
                      {ok, Val} ->
                          Fun0(Key, Val, Acc, Scope);
                      undefined ->
                          {Acc, Scope}
                  end
          end,
    rt_fold(Fun, Acc0, Scope0, Keys, []).

%%====================================================================
%% Rose tree operations
%%====================================================================

-spec rt_add(lee:key(), rose_tree()) -> rose_tree().
rt_add([A], Tree) ->
    case Tree of
        #{A := _} -> Tree;
        _         -> Tree #{A => #{}}
    end;
rt_add([A|B], Tree) ->
    Children0 = maps:get(A, Tree, #{}),
    Children = rt_add(B, Children0),
    Tree #{A => Children}.

-spec rt_del(lee:key(), rose_tree()) -> rose_tree().
rt_del([A], Tree) ->
    case Tree of
        #{A := Children} ->
            case maps:size(Children) of
                0 -> maps:without([A], Tree);
                _ -> error({A, Tree})
            end;
        _ ->
            Tree
    end;
rt_del([A|B], Tree) ->
    case Tree of
        #{A := Children} ->
            Tree #{A => rt_del(B, Children)};
        _ ->
            Tree
    end.

rt_fold(Fun, Acc, Scope, Tree) ->
    rt_fold(Fun, Acc, Scope, Tree, []).

rt_fold(Fun, Acc0, Scope0, Keys, Prefix0) ->
    maps:fold( fun(K, Children, Acc1) ->
                       Prefix = Prefix0 ++ [K],
                       {Acc, Scope} = Fun(Prefix, Acc1, Scope0),
                       rt_fold(Fun, Acc, Scope, Children, Prefix)
               end
             , Acc0
             , Keys
             ).

-spec rt_list_children(lee:key(), rose_tree()) -> [lee:key()].
rt_list_children(Parent, Tree) ->
    rt_fold( fun(Key, Acc, _) -> {[Parent ++ Key|Acc], ?unused} end
           , [Parent]
           , ?unused
           , goto(Parent, Tree)
           ).

%%====================================================================
%% Internal functions
%%====================================================================

-spec transform_patch(data(A), patch(A)) ->
                             {[lee:key()], [{lee:key(), A}]}.
transform_patch(#lee_tree{backend = Backend, data = Data}, Patch) ->
    {ok, Tree} = Backend:get(?rose_tree, Data),
    {Del0, Set} = separate_patch_operations(Patch, {[], []}),
    Del1 = lists:append([rt_list_children(I, Tree) || I <- Del0]),
    %% TODO: Optimize me
    %% Reverse lexicographic order ensures that children get deleted
    %% before parents:
    Del = lists:reverse(lists:sort(Del1)),
    {Del, Set}.

separate_patch_operations([], Acc) ->
    Acc;
separate_patch_operations([{rm, K} | Rest], {Del, Set}) ->
    separate_patch_operations(Rest, {[K | Del], Set});
separate_patch_operations([{set, K, V} | Rest], {Del, Set}) ->
    separate_patch_operations(Rest, {Del, [{K, V} | Set]}).

-spec goto(lee:key(), rose_tree()) -> rose_tree().
goto([], Tree) ->
    Tree;
goto([A|Rest], Tree) ->
    case Tree of
        #{A := T} -> goto(Rest, T);
        _         -> #{}
    end.

-spec list(rose_tree(), lee:key(), lee:key()) -> [lee:key()].
list(_, Prefix, []) ->
    [lists:reverse(Prefix)];
list(Keys, Prefix, [?children|Rest]) ->
    lists:append([ list(V, [K | Prefix], Rest)
                   || {K, V} <- maps:to_list(Keys)
                 ]);
list(Keys, Prefix, [K|Rest]) ->
    case Keys of
        #{K := V} ->
            list(V, [K | Prefix], Rest);
        _ ->
            []
    end.
