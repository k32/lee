%% Simple config storage type that stores everything in a map
-module(lee_map_storage).

-behavior(lee_storage).

-include("lee.hrl").

-export([ create/1
        , get/2
        , put/2
        ]).

create(_) ->
    #{}.

get(Key, Map) ->
    case Map of
        #{Key := Val} ->
            {ok, Val};
        #{} ->
            undefined
    end.

put(Data, NewData0) ->
    ChildrenLists = make_children_lists(NewData0),
    NewData = maps:merge(maps:from_list(NewData0), ChildrenLists),
    maps:merge(Data, NewData).

make_children_lists(Vals) ->
    lists:foldl(fun make_children_lists_/2, #{}, Vals).

make_children_lists_({Key0, _}, Acc0) ->
    case split_key_rev(Key0) of
        Key0 ->
            Acc0;
        {Key, Instance} ->
            Acc = make_children_lists_({Key, undefined}, Acc0),
            maps:update_with( Key ++ [?children]
                            , fun(Set) -> ordsets:add_element(Instance, Set) end
                            , [Instance]
                            , Acc
                            )
    end.

split_key_rev(Key0) ->
    Pred = fun(?lcl(_)) -> false;
              (_)       -> true
           end,
    case lists:splitwith(Pred, lists:reverse(Key0)) of
        {_, [?lcl(Instance)|Rest]} ->
            {lists:reverse(Rest), Instance};
        _ ->
            Key0
    end.
