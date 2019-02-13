-ifndef(LEE_HRL).
-define(LEE_HRL, true).

-define(children, '$children').

-define(lcl(A), {'$child', A}). %% Lee ChiLd

-define(map_key, 'map_key').

%% Internal mnode definition
-record(mnode,
        { metatypes = []    :: ordsets:set(atom())
        , metaparams = #{}  :: map()
        }).

-record(type,
        { id                :: lee:key()
        , refinement = #{}  :: map()
        , parameters = []   :: [lee:type()]
        }).

-endif.
