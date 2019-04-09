-module(lee_model).

%% API exports
-export([ compile/2
        , compile_module/1
        , decompile_module/1
        , traverse/3
        , traverse/4
        , map/2
        , map_with_key/2
        , get/2
        , get_meta/2
        , get_metatype_index/2
        , match/2
        , get_model_key/1
        , merge/1
        , split_key/1
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

%% @doc Merge multiple model and metamodel modules to a
%% machine-friendly form.
-spec compile([lee:lee_module()], [lee:lee_module()]) ->
                    {ok, #model{}} | {error, [term()]}.
compile(MetaModels0, Models0) ->
    MetaModels1 = [compile_module(I) || I <- MetaModels0],
    Models1 = [compile_module(I) || I <- Models0],
    case {merge(MetaModels1), merge(Models1)} of
        {{ok, MetaModel}, {ok, Model}} ->
            {ok, #model{ metamodel      = MetaModel
                       , model          = Model
                       , meta_class_idx = mk_metatype_index(Model)
                       }};
        {T1, T2} ->
            {error, [Err || {error, Err} <- [T1, T2]]}
    end.

%% @doc Decompile cooked module back to raw state
-spec decompile_module(lee:cooked_module()) -> lee:module().
decompile_module(Module0) ->
    Module1 = [{full_split_key(K), V} || {K, V} <- maps:to_list(Module0)],
    %% Sort keys lexicographically to ensure that all children are
    %% located immediately after the parent in the list:
    Module2 = lists:sort(Module1),
    decompile_module(#{}, Module2).

%% @doc Merge multiple model fragments while checking for clashing
%% names
-spec merge([lee:cooked_module(), ...]) -> {ok, lee:cooked_module()}
                                         | {error, term()}.
merge([]) ->
    {ok, #{}};
merge(L = [M|T]) ->
    Result = lists:foldl(fun maps:merge/2, M, T),
    ExpectedSize = lists:sum([maps:size(I) || I <- L]),
    case maps:size(Result) of
        ExpectedSize ->
            {ok, Result};
        _ ->
            %% Size of the resulting map is lesser than the sum of the
            %% original modules, it means there are clashing keys
            {_, Clashing} = lists:foldl( fun(K, {Seen, Clash0}) ->
                                                 Clash =
                                                     case Seen of
                                                         #{K := _} ->
                                                             Clash0 #{K => []};
                                                         _ ->
                                                             Clash0
                                                     end,
                                                 {Seen #{K => []}, Clash}
                                         end
                                       , {#{}, #{}}
                                       , L),
            {error, {clashing_keys, Clashing}}
    end.

%% @doc Get a node from the model, assuming that it is present
-spec get(lee:model_key(), lee:model() | lee:module()) -> #mnode{}.
get(Id, #model{model = Module}) ->
    maps:get(Id, Module);
get(Id, Module) ->
    maps:get(Id, Module).

%% @doc Get a node from the metamodel, assuming that it is present
-spec get_meta(lee:model_key(), lee:model()) -> #mnode{}.
get_meta(Id, #model{metamodel = Module}) ->
    maps:get(Id, Module).

-spec map( fun((lee:properties()) -> lee:properties())
         , lee:module()
         ) -> lee:module().
map(Fun, M) ->
    map_with_key(fun(_, Attrs) -> Fun(Attrs) end, M).

-spec map_with_key( fun((lee:model_key(), lee:properties()) -> lee:properties())
                  , lee:module()
                  ) -> lee:module().
map_with_key(Fun, M) ->
    {Term, _Acc} =
        traverse( fun(Key, MO, _) ->
                          case MO of
                              {Metatype, Attrs} ->
                                  {{Metatype, Fun(Key, Attrs)}, undefined};
                              {Metatype, Attrs, Children} ->
                                  {{Metatype, Fun(Key, Attrs), Children}, undefined}
                          end
                  end
                , undefined
                , M
                ),
    Term.

%% @doc Recursion schema for model traversal
-spec traverse( fun((lee:model_key(), lee:mnode(), Acc) -> {lee:mnode(), Acc})
              , Acc
              , Model
              ) -> {Model, Acc}
              when Acc   :: term()
                 , Model :: lee:model() | lee:cooked_module().
traverse(Fun, AccIn, M) ->
    traverse( fun(Key, MOC0, Acc0, unused) ->
                      {MOC, Acc} = Fun(Key, MOC0, Acc0),
                      {MOC, Acc, unused}
              end
            , AccIn
            , unused
            , M
            ).

%% @doc Recursion schema for model traversal with scope
-spec traverse( fun((lee:model_key(), lee:mnode(), Acc, Scope) -> {lee:mnode(), Acc, Scope})
              , Acc
              , Scope
              , Model
              ) -> {Model, Acc}
              when Acc   :: term()
                 , Scope :: term()
                 , Model :: lee:model() | lee:module().
traverse(Fun, Acc0, Scope0, M0 = #model{model = Module0}) ->
    Module1 = decompile_module(Module0),
    %% Ugly: we lose nested structure of the model during compilation,
    %% but we need it for traversal. So we decompile it here \^////
    {Module, Acc} = traverse(Fun, Acc0, Scope0, Module1),
    {M0#model{model = compile_module(Module)}, Acc};
traverse(Fun, Acc0, Scope0, Module0) ->
    traverse([], Fun, Acc0, Scope0, Module0).

%% Transform instance key to model key
-spec get_model_key(lee:key()) -> lee:model_key().
get_model_key([]) ->
    [];
get_model_key([?lcl(_) | T]) ->
    [?children | get_model_key(T)];
get_model_key([A|T]) ->
    [A | get_model_key(T)].

%% Checks whether an instance key matches with a mnode key
-spec match(lee:model_key(), lee:key()) -> boolean().
match(MK, IK) ->
    get_model_key(IK) =:= MK.

%% Split a key into base part and required part. Consider an example:
%% `[a, '$children', b, '$children', c]' [a] may or may not have
%% children, same goes for `[a, X, b]' Hence
%% `[a, '$children', b, $children']' is base of the key and [c] is
%% "required part"
-spec split_key(lee:model_key()) -> {lee:model_key(), lee:model_key()}.
split_key(K) ->
    {Req0, Base0} = lists:splitwith( fun(I) -> I =/= ?children end
                                   , lists:reverse(K)
                                   ),
    {lists:reverse(Base0), lists:reverse(Req0)}.

-spec full_split_key(lee:model_key()) -> [lee:model_key()].
full_split_key(Key) ->
    case lists:splitwith(fun(I) -> I =/= ?children end, Key) of
        {A, []} ->
            [A];
        {A, [?children | B]} ->
            [A | full_split_key(B)]
    end.

%% @doc Get an index of mnodes belonging to metatypes
-spec get_metatype_index(lee:metatype(), lee:model()) ->
                                ordets:set(lee:model_key()).
get_metatype_index(MT, #model{meta_class_idx = Idx}) ->
    maps:get(MT, Idx, []).

%%====================================================================
%% Internal functions
%%====================================================================

-spec compile_module(lee:module()) -> lee:cooked_module().
compile_module(Module) ->
    {_, Acc} = traverse( fun(Key, Node0, Acc) ->
                                 case Node0 of
                                     {MT0, MP}    -> ok;
                                     {MT0, MP, _} -> ok
                                 end,
                                 MT = ordsets:from_list(MT0),
                                 Node = #mnode{ metatypes = MT0
                                              , metaparams = MP
                                              },
                           {Node0, Acc #{Key => Node}}
                         end
                       , #{}
                       , Module),
    Acc.

decompile_module(Acc, []) ->
    Acc;
decompile_module(Acc0, [{[K1], V1} | Rest0]) ->
    #mnode{ metatypes = MTs
          , metaparams = MPs
          } = V1,
    FindMyChildren = fun({[K|_], _}) -> K1 =:= K end,
    {MyChildren0, Rest} = lists:splitwith(FindMyChildren, Rest0),
    MyChildren1 = [{tl(K), V} || {K, V} <- MyChildren0],
    MyChildren = decompile_module(#{}, MyChildren1),
    Acc1 = raw_module_add_node(Acc0, K1, {MTs, MPs, MyChildren}),
    decompile_module(Acc1, Rest).

traverse(Key0, Fun, AccIn, ScopeIn, M) when is_map(M) ->
    maps:fold( fun(K, Val0, {Map0, Acc0}) ->
                       Key = Key0 ++ [K],
                       {Val, Acc} = traverse(Key, Fun, Acc0, ScopeIn, Val0),
                       {Map0#{K => Val}, Acc}
               end
             , {#{}, AccIn}
             , M
             );
traverse(Key, Fun, Acc0, Scope0, MO0) ->
    {MO, Acc1, Scope1} = Fun(Key, MO0, Acc0, Scope0),
    case MO of
        {_, _} ->
            {MO, Acc1};
        {_, _, []} ->
            {MO, Acc1};
        {Metatype, Attrs, Children0} ->
            {Children, Acc} = traverse(Key ++ [?children], Fun, Acc1, Scope1, Children0),
            {{Metatype, Attrs, Children}, Acc}
    end.

%% @doc Make an index of MOCs belonging to metatypes
-spec mk_metatype_index(lee:lee_module()) -> metatype_index().
mk_metatype_index(MF) ->
    maps:fold(fun mk_metatype_index_/3, #{}, MF).

mk_metatype_index_(Key, #mnode{metatypes = MetaTypes}, Acc0) ->
    lists:foldl( fun(MT, Acc) ->
                         S0 = maps:get(MT, Acc, ordsets:new()),
                         Acc#{MT => ordsets:add_element(Key, S0)}
                 end
               , Acc0
               , MetaTypes).

raw_module_add_node(Module, [Key], Node) ->
    Module #{Key => Node};
raw_module_add_node(Module, [Key|Rest], Node) ->
    Children = maps:get(Key, Module, #{}),
    Module #{Key => raw_module_add_node(Children, Rest, Node)}.
