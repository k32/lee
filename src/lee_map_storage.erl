%% Simple config storage type that stores avarything in a map
-module(lee_map_storage).

-behavior(lee_storage).

-export([ create/1
        , get/3
        , put/3
        , list/3
        ]).

create(_) ->
    #{}.

get(_, Map, Key) ->
    case Map of
        #{Key := Val} ->
            {ok, Val};
        _ ->
            undefined
    end.

list(Model, Map, Pattern) ->
    L = length(Pattern),
    lists:usort(
      lists:filtermap( fun(K0) ->
                               K = lists:sublist(K0, L),
                               case lee_model:match(Model, K, Pattern) of
                                   true -> {true, K};
                                   false -> false
                               end
                       end
                     , maps:keys(Map)
                     )).

put(_, Map, List) ->
    maps:merge(Map, maps:from_list(List)).
