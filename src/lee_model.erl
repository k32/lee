-module(lee_model).

%% API exports
-export([ merge/1
        , merge/2
        , create/2
        , desugar/1
        , traverse/3
        , map/2
        , map_with_key/2
        , get/2
        , mk_metatype_index/1
        , match/3
        , optional_part/2
        ]).

%%====================================================================
%% Types
%%====================================================================

-include("lee_internal.hrl").

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

%%====================================================================
%% API functions
%%====================================================================

%% @doc Merge multiple model fragments with the metamodel
-spec create([lee:model_fragment()], [lee:model_fragment()]) ->
                    {ok, #model{}} | {error, [term()]}.
create(MetaModels, Models) ->
    case [merge(MetaModels), merge(Models)] of
        [{ok, MMs}, {ok, Ms}] ->
            {ok, #model{ metamodel = desugar(MMs)
                       , model     = desugar(Ms)
                       }};
        T ->
            {error, [Err || {error, Err} <- T]}
    end.

%% @doc Merge multiple model fragments while checking for clashing
%% names
-spec merge([A]) -> {ok, A}
                  | {error, term()}
      when A :: lee:model_fragment() | lee:model().
merge(L = [#model{metamodel = MM0}|_]) ->
    case merge([M || #model{model = M} <- L]) of
        {ok, M} ->
            #model{ metamodel = MM0
                  , model     = M
                  };
        Err ->
            Err
    end;
merge(FragList) ->
    try
        {ok, lists:foldl( fun(MF, Acc) ->
                                  merge([], Acc, MF)
                          end
                        , #{}
                        , FragList
                        )}
    catch Err = {clashing_keys, _} ->
            {error, Err}
    end.

%% @doc Merge two models or model fragments while checking for
%% clashing names
-spec merge(A, A) -> {ok, A}
                   | {error, term()}
      when A :: lee:model_fragment() | lee:model().
merge( #model{metamodel = MM1, model = M1}
     , #model{metamodel = MM2, model = M2}
     ) ->
    case {MM1 =:= MM2, merge(M1, M2)} of
        {true, {ok, M}} ->
            #model{ metamodel = MM1
                  , model     = M
                  };
        {false, _} ->
            {error, different_metamodels};
        {_, Err} ->
            Err
    end;
merge(M1, M2) ->
    try
        {ok, merge([], M1, M2)}
    catch
        Err = {clashing_keys, _} ->
            {error, Err}
    end.

%% @doc Get a MOC from the model, assumes that the key is present and
%% non-empty
-spec get(lee:key(), lee:model_fragment()) ->
             lee:moc().
get([Id], MF) ->
    maps:get(Id, MF);
get([Id|Rest], MF) ->
    case maps:get(Id, MF) of
        Map when is_map(Map) -> %% Namespace
            get(Rest, Map);
        {_, _, Children} -> %% Map
            case Rest of
                [_|Rest1] ->
                    get(Rest1, Children);
                [_] ->
                    error(badkey)
            end
    end.

%% @doc Transform all MOs to fully-qualified form
-spec desugar(lee:model_fragment()) -> lee:model_fragment().
desugar(M0) ->
    {M, _} = traverse(fun desugar_mo/3, undefined, M0),
    M.

-spec map( fun((lee:properties()) -> lee:properties())
         , lee:model_fragment()
         ) -> lee:model_fragment().
map(Fun, M) ->
    map_with_key( fun(_, Attrs) ->
                          Fun(Attrs)
                  end
                , M
                ).

-spec map_with_key( fun((lee:key(), lee:properties()) -> lee:properties())
                  , lee:model_fragment()
                  ) -> lee:model_fragment().
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
-spec traverse( fun((lee:key(), lee:moc(), Acc) -> {lee:moc(), Acc})
              , Acc
              , lee:model_fragment()
              ) -> {lee:model_fragment(), Acc}
              when Acc :: term().
traverse(Fun, Acc0, M) ->
    traverse([], Fun, Acc0, M).

%% @doc Make an index of MOCs belonging to metatypes. Assumes
%% desugared model
-spec mk_metatype_index(lee:model_fragment()) ->
                           #{lee:metatype() => map_sets:set(lee:key())}.
mk_metatype_index(MF) ->
    {_, Idx} = traverse( fun mk_metatype_index_/3
                       , #{}
                       , MF
                       ),
    Idx.

%% Checks whether two keys match or not
-spec match(lee:model(), lee:key(), lee:key()) ->
                   boolean().
match(#model{model = Model}, K1, K2) ->
    do_match(Model, K1, K2).

%% Split key into optional and mandatory parts
-spec optional_part(lee:model(), lee:key()) ->
                   {lee:key(), lee:key()}.
optional_part(#model{model = Model}, K) ->
    Optional = do_optional_part(Model, K, [], []),
    {Optional, lists:nthtail(length(Optional), K)}.

%%====================================================================
%% Internal functions
%%====================================================================

merge(Key0, M1, M2) ->
    maps:fold( fun(K, N1, Acc) ->
                       Key = Key0 ++ [K],
                       case Acc of
                           #{K := N2} when is_map(N1)
                                         , is_map(N2) ->
                               %% Both elements are namespaces, merge them
                               Acc#{K => merge(Key, N1, N2)};
                           #{K := _} ->
                               %% TODO: currently we stop on the first
                               %% error, it's not user-friendly
                               throw({clashing_keys, [Key]});
                           _ ->
                               Acc#{K => N1}
                       end
               end
             , M1
             , M2
             ).

traverse(Key0, Fun, AccIn, M) when is_map(M) ->
    maps:fold( fun(K, Val0, {Map0, Acc0}) ->
                       Key = Key0 ++ [K],
                       {Val, Acc} = traverse(Key, Fun, Acc0, Val0),
                       {Map0#{K => Val}, Acc}
               end
             , {#{}, AccIn}
             , M
             );
traverse(Key, Fun, Acc0, MO0) ->
    {MO, Acc1} = Fun(Key, MO0, Acc0),
    case MO of
        {_, _} ->
            {MO, Acc1};
        {_, _, []} ->
            {MO, Acc1};
        {Metatype, Attrs, Children0} ->
            {Children, Acc} = traverse(Key ++ [?children], Fun, Acc1, Children0),
            {{Metatype, Attrs, Children}, Acc}
    end.

mk_metatype_index_(Key, MOC = {Metatypes, _, _}, Acc0) ->
    Acc = lists:foldl( fun(MT, Acc) ->
                               S0 = maps:get(MT, Acc, #{}),
                               Acc#{MT => map_sets:add_element(Key, S0)}
                       end
                     , Acc0
                     , Metatypes
                     ),
    {MOC, Acc}.

desugar_mo(_, {MetaTypes, Attrs}, _) ->
    {{MetaTypes, Attrs, #{}}, undefined};
desugar_mo(_, MO = {_, _, _}, _) ->
    {MO, undefined}.

do_match(_, [], []) ->
    true;
do_match(Model, [NS|T1], [NS|T2]) when is_map(Model) ->
    #{NS := Rest} = Model,
    do_match(Rest, T1, T2);
do_match({_MetaType, _Attrs, Rest}, [_|T1], [_|T2]) ->
    do_match(Rest, T1, T2);
do_match(_, _, _) ->
    false.

do_optional_part(_, [], Visited, Optional) ->
    lists:reverse(Optional);
do_optional_part(Model, _Key = [Node|Rest], Visited0, Optional) ->
    case maps:get(Node, Model) of
        NS when is_map(NS) ->
            do_optional_part(NS, Rest, [Node|Visited0], Optional);
        {_MetaType, _Attrs, Children} ->
            case Rest of
                [OptNode|Rest1] ->
                    Visited = [OptNode, Node | Visited0],
                    do_optional_part(Children, Rest1, Visited, Visited);
                _ ->
                    lists:reverse(Optional)
            end
    end.
