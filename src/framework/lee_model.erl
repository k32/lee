%% @doc This module defines functions for manipulating Lee models.
-module(lee_model).

%% API exports
-export([ compile/2
        , compile_module/1
        , map_vals/2
        , fold/3
        , fold/4
        , get/2
        , get_meta/2
        , get_metatype_index/2
        , match/2
        , get_model_key/1
        , merge/1
        , merge/2
        , split_key/1
        , full_split_key/1
        , clone/4
        ]).

-export_type([ metatype_index/0
             ]).

-include("lee_internal.hrl").

%%====================================================================
%% Types
%%====================================================================
-type metatype_index() :: #{lee:metatype() => ordsets:set(lee:model_key())}.

%%====================================================================
%% API functions
%%====================================================================

%% @doc Merge multiple model and metamodel modules into a
%% machine-friendly form.
-spec compile([M], [M]) -> {ok, #model{}} | {error, [term()]}
            when M :: lee:lee_module() | lee:cooked_module().
compile(MetaModels0, Models0) ->
    MetaModels = [compile_module(I) || I <- MetaModels0],
    Models = [compile_module(I) || I <- Models0],
    case {merge(MetaModels), merge(Models)} of
        {{ok, MetaModel}, {ok, Model}} ->
            Result = #model{ metamodel      = MetaModel
                           , model          = Model
                           , meta_class_idx = mk_metatype_index(Model)
                           },
            case lee:meta_validate(Result) of
                {ok, _} ->
                    {ok, Result};
                {error, Err, _Warn} ->
                    {error, {validation_error, Err}}
            end;
        {T1, T2} ->
            {error, [Err || {error, Err} <- [T1, T2]]}
    end.

%% @doc Merge multiple Lee model modules into a single module
-spec merge([M]) -> {ok, lee:cooked_module()} | {error, term()}
               when M :: lee:cooked_module() | lee:lee_module().
merge(L) ->
    M0 = lee_storage:new(lee_map_storage),
    try
        {ok, lists:foldl( fun(M1, Acc) ->
                                  case merge(M1, Acc) of
                                      {ok, M2} -> M2;
                                      Err      -> throw(Err)
                                  end
                          end
                        , M0
                        , L
                        )}
    catch
        Err -> Err
    end.

%% @doc Merge two Lee model modules into a single module
-spec merge(M, M) -> {ok, lee:cooked_module()} | {error, term()}
               when M :: lee:cooked_module() | lee:lee_module().
merge(M1_0, M2) ->
    M1 = compile_module(M1_0),
    Fun = fun(Key, MNode, Acc) ->
                  [{set, Key, MNode} | Acc]
          end,
    Patch = fold(Fun, [], M2),
    Collisions = [K || {set, K, _} <- Patch,
                       case lee_storage:get(K, M1) of
                           {ok, _}   -> true;
                           undefined -> false
                       end],
    case Collisions of
        [] ->
            {ok, lee_storage:patch(M1, Patch)};
        _ ->
            {error, {clashing_keys, Collisions}}
    end.

%% @doc Get a node from the model, assuming that it is present
-spec get(lee:model_key(), lee:model() | lee:module()) -> #mnode{}.
get(Id, #model{model = Module}) ->
    get(Id, Module);
get(Id, Module) ->
    case lee_storage:get(Id, Module) of
        {ok, Val} -> Val;
        _         -> error({bad_model_key, Id})
    end.

%% @doc Get a node from the metamodel, assuming that it is present
-spec get_meta(lee:model_key(), lee:model()) -> #mnode{}.
get_meta(Id, #model{metamodel = Module}) ->
    get(Id, Module).

%% @doc Apply a function to all nodes of a raw model module. Doesn't
%% traverse into child nodes
-spec map_vals( fun((lee:mnode()) -> lee:mnode())
              , lee:module()
              ) -> lee:module().
map_vals(Fun, Model) ->
    maps:map( fun(_, Val) when is_map(Val) ->
                      map_vals(Fun, Val);
                 (_, Node) ->
                      Fun(Node)
              end
            , Model).

%% @doc Recursion schema for model fold
-spec fold( fun((lee:model_key(), #mnode{}, Acc) -> Acc)
          , Acc
          , Model
          ) -> Acc
      when Acc   :: term()
         , Model :: lee:model() | lee:module().
fold(Fun0, Acc, Data) ->
    Fun = fun(Key, Val, Acc, _) ->
                  {Fun0(Key, Val, Acc), ?unused}
          end,
    fold(Fun, Acc, ?unused, Data).

%% @doc Recursion schema for model fold with scope
-spec fold( fun((lee:model_key(), #mnode{}, Acc, Scope) -> {Acc, Scope})
          , Acc
          , Scope
          , Model
          ) -> Acc
      when Model :: lee:model() | lee:lee_module() | lee:cooked_module().
fold(Fun, Acc, Scope, #model{model = Model}) -> %% Fold over cooked model
    lee_storage:fold(Fun, Acc, Scope, Model);
fold(Fun, Acc, Scope, Module) when is_map(Module) -> %% Fold over raw model
    fold([], Fun, Acc, Scope, Module);
fold(Fun, Acc, Scope, Model) -> %% Fold over cooked module
    lee_storage:fold(Fun, Acc, Scope, Model).

%% @doc Transform instance key to model key
-spec get_model_key(lee:key()) -> lee:model_key().
get_model_key([]) ->
    [];
get_model_key([?lcl(_) | T]) ->
    [?children | get_model_key(T)];
get_model_key([A|T]) ->
    [A | get_model_key(T)].

%% @doc Check whether an instance key matches a mnode key
-spec match(lee:model_key(), lee:key()) -> boolean().
match(MK, IK) ->
    get_model_key(IK) =:= MK.

%% @doc Split a key into a <i>base</i> part and a <i>required
%% part</i>. Child object with <i>required part</i> of the key is
%% mandatory if object with <i>base</i> key is present.
%%
%% Consider an example: ```[a, '$children', b, '$children',
%% c]''' Here `[a]' may or may not have children, same goes for `[a,
%% X, b]' Hence ```[a, '$children', b, $children']''' is the
%% <i>base</i> of the key and `[c]' is the <i>required part</i>.
-spec split_key(lee:model_key()) -> {lee:model_key(), lee:model_key()}.
split_key(K) ->
    {Req0, Base0} = lists:splitwith( fun(I) -> I =/= ?children end
                                   , lists:reverse(K)
                                   ),
    {lists:reverse(Base0), lists:reverse(Req0)}.

-spec full_split_key(lee:key()) -> [lee:key()].
full_split_key(Key) ->
    Pred = fun(?children) -> false;
              (?lcl(_))   -> false;
              (_)         -> true
           end,
    lee_lib:splitl(Pred, Key).

%% @doc Get an index of mnodes belonging to metatypes
-spec get_metatype_index(lee:metatype(), lee:model()) ->
                                ordets:set(lee:model_key()).
get_metatype_index(MT, #model{meta_class_idx = Idx}) ->
    maps:get(MT, Idx, []).

%% @doc Copy model from one lee_storage to another
-spec clone(lee:model(), module(), map(), map()) -> lee:model().
clone(M0 = #model{metamodel = A, model = B}, Backend, BO1, BO2) ->
    M0#model{ metamodel = lee_storage:clone(A, Backend, BO1)
            , model = lee_storage:clone(B, Backend, BO2)
            }.

%%====================================================================
%% Internal functions
%%====================================================================

-spec compile_module(lee:module() | lee:cooked_module()) -> lee:cooked_module().
compile_module(Module) when is_map(Module) ->
    Fun = fun(Key, MNode, Acc) ->
                  [{set, Key, MNode} | Acc]
          end,
    lee_storage:patch( lee_storage:new(lee_map_storage)
                     , fold(Fun, [], Module)
                     );
compile_module(Module) when ?is_storage(Module) -> %% Already cooked
    Module.

%% Fold over raw model:
fold(Key0, Fun, AccIn, ScopeIn, M) when is_map(M) -> %% Namespace
    maps:fold( fun(K, Children, Acc0) ->
                       Key = Key0 ++ [K],
                       fold(Key, Fun, Acc0, ScopeIn, Children)
               end
             , AccIn
             , M
             );
fold(Key, Fun, Acc0, Scope0, MN0) ->
    case MN0 of
        {MT, MP, Children} -> ok;
        {MT, MP}           -> Children = #{}
    end,
    MNode = #mnode{ metatypes = ordsets:from_list(MT)
                  , metaparams = MP
                  },
    {Acc, Scope} = Fun(Key, MNode, Acc0, Scope0),
    fold(Key ++ [?children], Fun, Acc, Scope, Children).

%% @doc Make an index of MOCs belonging to metatypes
-spec mk_metatype_index(lee:cooked_module()) -> metatype_index().
mk_metatype_index(MF) ->
    lee_storage:fold(fun mk_metatype_index_/3, #{}, MF).

mk_metatype_index_(Key, #mnode{metatypes = MetaTypes}, Acc0) ->
    lists:foldl( fun(MT, Acc) ->
                         S0 = maps:get(MT, Acc, ordsets:new()),
                         Acc#{MT => ordsets:add_element(Key, S0)}
                 end
               , Acc0
               , MetaTypes).
